import CoreServices
import Dispatch
import Foundation
@testable import RepoPromptApp
import XCTest

final class FileSystemLivenessCorrectionTests: XCTestCase {
    func testMailboxRejectsCapturedCallbackFromPriorIngressGenerationAfterRestart() {
        let mailbox = FileSystemWatcherIngressMailbox(maxQueuedRawEntries: 10)
        let oldGeneration: UInt64 = 11
        let newGeneration: UInt64 = 12
        let oldPayload = payload(path: "/fixture/old.swift", eventID: 100)
        let newPayload = payload(path: "/fixture/new.swift", eventID: 1)

        mailbox.startAccepting(for: oldGeneration)
        XCTAssertNotNil(
            mailbox.accept(
                oldPayload,
                ingressGeneration: oldGeneration,
                lifecycleCorrelation: nil,
                scheduleDrain: nil
            )
        )

        mailbox.stopAcceptingAndDiscardPending()
        mailbox.startAccepting(for: newGeneration)

        XCTAssertNil(
            mailbox.accept(
                oldPayload,
                ingressGeneration: oldGeneration,
                lifecycleCorrelation: nil,
                scheduleDrain: nil
            )
        )
        guard let acceptedNew = mailbox.accept(
            newPayload,
            ingressGeneration: newGeneration,
            lifecycleCorrelation: nil,
            scheduleDrain: nil
        ) else {
            return XCTFail("Expected the current-generation callback to be accepted")
        }

        guard let retained = mailbox.takeNextAcceptedPayload() else {
            return XCTFail("Expected the current-generation payload to remain queued")
        }
        XCTAssertEqual(retained.ingressGeneration, newGeneration)
        XCTAssertEqual(retained.acceptedHighWatermark, acceptedNew)
    }

    func testWrappedCutCannotUseOldHighWatermarkAndOnlyFreshGenerationRecovers() async throws {
        let barrier = FSEventAsyncDeliveryBarrier(
            scheduleDeadline: { _, action in action() }
        )
        let oldGeneration = barrier.currentGeneration
        barrier.recordDelivered(eventIDs: [100], generation: oldGeneration)

        let newGeneration = barrier.reset(ifCurrent: oldGeneration)
        XCTAssertNotNil(newGeneration)
        let staleGenerationDelivered = await barrier.waitUntilDelivered(
            5,
            generation: oldGeneration
        )
        XCTAssertFalse(staleGenerationDelivered)

        barrier.recordDelivered(eventIDs: [5], generation: oldGeneration)
        let oldWatermarkDeliveredToReplacement = try await barrier.waitUntilDelivered(
            5,
            generation: XCTUnwrap(newGeneration)
        )
        XCTAssertFalse(oldWatermarkDeliveredToReplacement)

        try barrier.recordDelivered(eventIDs: [5], generation: XCTUnwrap(newGeneration))
        let freshGenerationDelivered = try await barrier.waitUntilDelivered(
            5,
            generation: XCTUnwrap(newGeneration)
        )
        XCTAssertTrue(freshGenerationDelivered)
    }

    func testFileSystemWrappedStreamFailsClosedInsteadOfRestartingWithOldCut() async throws {
        let root = try makeTestDirectory(name: "FileSystemWrappedStream")
        let service = try await FileSystemService(
            path: root.path,
            respectRepoIgnore: false,
            respectCursorignore: false,
            skipSymlinks: true,
            isTestMode: true
        )
        let deliveryGeneration = service.fseventDeliveryBarrier.currentGeneration
        let streamGeneration = await service.fseventStreamGenerationForTesting()
        let ingressGeneration = await service.watcherIngressGenerationForTesting()

        await service.handleFSEventIDsWrappedForTesting(
            streamGeneration: streamGeneration,
            ingressGeneration: ingressGeneration,
            deliveryGeneration: deliveryGeneration
        )

        let recoveryRequired = await service.fseventRecoveryRequiredForTesting()
        XCTAssertTrue(recoveryRequired)
        XCTAssertNotEqual(service.fseventDeliveryBarrier.currentGeneration, deliveryGeneration)
        do {
            try await service.startWatchingForChanges()
            XCTFail("A wrapped stream must remain unavailable until fresh root recovery")
        } catch let error as FileSystemWatcherActivationError {
            XCTAssertEqual(error, .eventIDsWrapped(path: root.path))
        }
    }

    func testCallbackObservedWrapRemainsStickyAcrossStopBeforeActorHandlerRestart() async throws {
        let root = try makeTestDirectory(name: "FileSystemCallbackWrapRestart")
        let service = try await FileSystemService(
            path: root.path,
            respectRepoIgnore: false,
            respectCursorignore: false,
            skipSymlinks: true,
            isTestMode: true
        )
        let deliveryGeneration = service.fseventDeliveryBarrier.currentGeneration

        await service.markFSEventIDsWrappedAtCallbackForTesting(deliveryGeneration: deliveryGeneration)
        await service.stopWatchingForChanges()

        let actorRecoveryRequired = await service.fseventRecoveryRequiredForTesting()
        XCTAssertFalse(actorRecoveryRequired, "The actor handler has not run in this interleaving")
        do {
            try await service.startWatchingForChanges()
            XCTFail("Callback-observed wrap must block restart before the actor handler runs")
        } catch let error as FileSystemWatcherActivationError {
            XCTAssertEqual(error, .eventIDsWrapped(path: root.path))
        } catch {
            XCTFail("Expected a wrapped-stream activation error, got: \(error)")
        }
    }

    func testActiveLoadedRootAutomaticallyReplacesWrappedServiceAndDeliversSubsequentMutation() async throws {
        let rootURL = try makeTestDirectory(name: "FileSystemActiveOwnerRecovery")
        try write("initial", to: rootURL.appendingPathComponent("Initial.swift"))
        let store = WorkspaceFileContextStore()
        let root = try await store.loadRoot(
            path: rootURL.path,
            respectRepoIgnore: false,
            respectCursorignore: false
        )
        let (publisherOpenings, publisherOpeningContinuation) = AsyncStream<Void>.makeStream()
        var publisherOpeningIterator = publisherOpenings.makeAsyncIterator()
        await store.setWatcherPublisherIngressDidOpenHandler { _, _ in
            publisherOpeningContinuation.yield(())
        }
        try await store.startWatchingRoot(id: root.id)
        guard await publisherOpeningIterator.next() != nil else {
            return XCTFail("Expected the active root publisher ingress to open")
        }
        guard let oldService = await store.fileSystemServiceForTesting(rootID: root.id) else {
            return XCTFail("Expected the demanded root to own a filesystem service")
        }
        let deliveryGeneration = oldService.fseventDeliveryBarrier.currentGeneration
        let streamGeneration = await oldService.fseventStreamGenerationForTesting()
        let ingressGeneration = await oldService.watcherIngressGenerationForTesting()

        await oldService.handleFSEventIDsWrappedForTesting(
            streamGeneration: streamGeneration,
            ingressGeneration: ingressGeneration,
            deliveryGeneration: deliveryGeneration
        )

        guard await publisherOpeningIterator.next() != nil else {
            return XCTFail("Expected callback-observed wrap to reopen publisher ingress automatically")
        }
        guard let recoveredService = await store.fileSystemServiceForTesting(rootID: root.id) else {
            return XCTFail("Expected the active root to retain a recovered filesystem service")
        }
        XCTAssertFalse(oldService === recoveredService)
        let recoveredFlag = await recoveredService.fseventRecoveryRequiredForTesting()
        XCTAssertFalse(recoveredFlag)

        let deltaEvents = await store.fileSystemDeltaEvents()
        var iterator = deltaEvents.makeAsyncIterator()
        let addedURL = rootURL.appendingPathComponent("AfterActiveRecovery.swift")
        try write("after recovery", to: addedURL)
        let accepted = try await store.acceptWatcherPayloadForTesting(
            rootID: root.id,
            events: [(
                absolutePath: addedURL.path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile
                ),
                eventId: 1
            )],
            scheduleDrain: false
        )
        guard let accepted else {
            return XCTFail("Expected a current-generation mutation after owner recovery")
        }
        let publicationSequence = await recoveredService.flushPendingEventsNow(
            throughAcceptedWatcherWatermark: accepted
        )
        await store.waitUntilPublisherIngressAppliedForTesting(
            rootID: root.id,
            servicePublicationSequence: publicationSequence
        )
        let event = await iterator.next()
        XCTAssertEqual(event?.delta, .fileAdded("AfterActiveRecovery.swift"))
        await store.stopWatchingRoot(id: root.id)
        await store.setWatcherPublisherIngressDidOpenHandler(nil)
        publisherOpeningContinuation.finish()
    }

    func testWrappedRecoveryRetainsManagedIgnoredFileForMutationAndDeletion() async throws {
        let rootURL = try makeTestDirectory(name: "FileSystemManagedIgnoredRecovery")
        let ignoredPath = "ManagedIgnored.swift"
        try write("ManagedIgnored.swift\n", to: rootURL.appendingPathComponent(".gitignore"))
        try write("initial", to: rootURL.appendingPathComponent(ignoredPath))
        let store = WorkspaceFileContextStore()
        let root = try await store.loadRoot(
            path: rootURL.path,
            respectRepoIgnore: true,
            respectCursorignore: false
        )
        let (publisherOpenings, publisherOpeningContinuation) = AsyncStream<Void>.makeStream()
        var publisherOpeningIterator = publisherOpenings.makeAsyncIterator()
        await store.setWatcherPublisherIngressDidOpenHandler { _, _ in
            publisherOpeningContinuation.yield(())
        }
        try await store.startWatchingRoot(id: root.id)
        guard await publisherOpeningIterator.next() != nil else {
            return XCTFail("Expected the managed-only test root publisher ingress to open")
        }
        _ = try await store.materializeCatalogFileAfterDiskWrite(
            rootID: root.id,
            relativePath: ignoredPath
        )
        guard let oldService = await store.fileSystemServiceForTesting(rootID: root.id) else {
            return XCTFail("Expected the managed-only root to own a filesystem service")
        }
        let deliveryGeneration = oldService.fseventDeliveryBarrier.currentGeneration
        let streamGeneration = await oldService.fseventStreamGenerationForTesting()
        let ingressGeneration = await oldService.watcherIngressGenerationForTesting()
        await oldService.handleFSEventIDsWrappedForTesting(
            streamGeneration: streamGeneration,
            ingressGeneration: ingressGeneration,
            deliveryGeneration: deliveryGeneration
        )
        guard await publisherOpeningIterator.next() != nil else {
            return XCTFail("Expected managed-only recovery to reopen publisher ingress")
        }
        guard let recoveredService = await store.fileSystemServiceForTesting(rootID: root.id) else {
            return XCTFail("Expected the managed-only root to retain a recovered service")
        }
        let filterCountBeforeMutation = await recoveredService.watcherEarlyFilterSnapshotForTesting().filteredEntryCount

        let modifiedAccepted = try await store.acceptWatcherPayloadForTesting(
            rootID: root.id,
            events: [(
                absolutePath: rootURL.appendingPathComponent(ignoredPath).path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile
                ),
                eventId: 2
            )],
            scheduleDrain: false
        )
        guard let modifiedAccepted else {
            return XCTFail("Managed-only mutation must remain visible to the replacement filter")
        }
        let modifiedPublicationSequence = await recoveredService.flushPendingEventsNow(
            throughAcceptedWatcherWatermark: modifiedAccepted
        )
        await store.waitUntilPublisherIngressAppliedForTesting(
            rootID: root.id,
            servicePublicationSequence: modifiedPublicationSequence
        )
        let retainedAfterMutation = await store.lookupPath(
            rootID: root.id,
            relativePath: ignoredPath
        )
        XCTAssertNotNil(retainedAfterMutation?.file)
        let filterCountAfterMutation = await recoveredService.watcherEarlyFilterSnapshotForTesting().filteredEntryCount
        XCTAssertEqual(filterCountAfterMutation, filterCountBeforeMutation)

        try FileManager.default.removeItem(at: rootURL.appendingPathComponent(ignoredPath))
        let removedAccepted = try await store.acceptWatcherPayloadForTesting(
            rootID: root.id,
            events: [(
                absolutePath: rootURL.appendingPathComponent(ignoredPath).path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemIsFile
                ),
                eventId: 3
            )],
            scheduleDrain: false
        )
        guard let removedAccepted else {
            return XCTFail("Managed-only deletion must remain visible to the replacement filter")
        }
        let removedPublicationSequence = await recoveredService.flushPendingEventsNow(
            throughAcceptedWatcherWatermark: removedAccepted
        )
        await store.waitUntilPublisherIngressAppliedForTesting(
            rootID: root.id,
            servicePublicationSequence: removedPublicationSequence
        )
        let removedRecord = await store.lookupPath(rootID: root.id, relativePath: ignoredPath)
        XCTAssertNil(removedRecord?.file)
        let filterCountAfterDeletion = await recoveredService.watcherEarlyFilterSnapshotForTesting().filteredEntryCount
        XCTAssertEqual(filterCountAfterDeletion, filterCountBeforeMutation)
        await store.stopWatchingRoot(id: root.id)
        await store.setWatcherPublisherIngressDidOpenHandler(nil)
        publisherOpeningContinuation.finish()
    }

    func testLoadedRootReplacesWrappedServiceAndDeliversSubsequentMutation() async throws {
        let rootURL = try makeTestDirectory(name: "FileSystemOwnerRecovery")
        try write("initial", to: rootURL.appendingPathComponent("Initial.swift"))
        let store = WorkspaceFileContextStore()
        let root = try await store.loadRoot(
            path: rootURL.path,
            respectRepoIgnore: false,
            respectCursorignore: false
        )
        guard let oldService = await store.fileSystemServiceForTesting(rootID: root.id) else {
            return XCTFail("Expected the loaded root to own a filesystem service")
        }
        let deliveryGeneration = oldService.fseventDeliveryBarrier.currentGeneration
        let streamGeneration = await oldService.fseventStreamGenerationForTesting()
        let ingressGeneration = await oldService.watcherIngressGenerationForTesting()
        await oldService.handleFSEventIDsWrappedForTesting(
            streamGeneration: streamGeneration,
            ingressGeneration: ingressGeneration,
            deliveryGeneration: deliveryGeneration
        )

        try await store.startWatchingRoot(id: root.id)
        guard let recoveredService = await store.fileSystemServiceForTesting(rootID: root.id) else {
            return XCTFail("Expected the recovered root to retain a filesystem service")
        }
        XCTAssertFalse(oldService === recoveredService)
        let recoveredFlag = await recoveredService.fseventRecoveryRequiredForTesting()
        XCTAssertFalse(recoveredFlag)
        let watcherIsActive = try await store.rootWatcherIsActiveForTesting(rootID: root.id)
        XCTAssertTrue(watcherIsActive)

        let deltaEvents = await store.fileSystemDeltaEvents()
        var iterator = deltaEvents.makeAsyncIterator()
        let addedURL = rootURL.appendingPathComponent("AfterRecovery.swift")
        try write("after recovery", to: addedURL)
        let accepted = try await store.acceptWatcherPayloadForTesting(
            rootID: root.id,
            events: [(
                absolutePath: addedURL.path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile
                ),
                eventId: 1
            )],
            scheduleDrain: false
        )
        XCTAssertNotNil(accepted)
        guard let accepted else {
            return XCTFail("Expected a current-generation mutation after explicit recovery")
        }
        let publicationSequence = await recoveredService.flushPendingEventsNow(
            throughAcceptedWatcherWatermark: accepted
        )
        await store.waitUntilPublisherIngressAppliedForTesting(
            rootID: root.id,
            servicePublicationSequence: publicationSequence
        )
        let event = await iterator.next()
        XCTAssertEqual(event?.delta, .fileAdded("AfterRecovery.swift"))
        await recoveredService.stopWatchingForChanges()
    }

    func testSeededPublicationPermitLinearizesCallbackWrapAfterAssignment() async throws {
        let (service, initializationID) = try await makeSeededServiceReadyForPublication(
            name: "FileSystemSeededPublicationPermit"
        )
        guard let proof = await service.activateSeededPublication(initializationID: initializationID) else {
            await service.abortSeededPreparation(initializationID: initializationID)
            return XCTFail("Expected a ready seeded service to activate")
        }

        let callbackReady = DispatchSemaphore(value: 0)
        let callbackMayProceed = DispatchSemaphore(value: 0)
        let callbackFinished = DispatchSemaphore(value: 0)
        let publicationCompleted = LivenessLockedValue(false)
        let callbackObservedPublication = LivenessLockedValue(false)
        let ownerRecoverySignaled = LivenessLockedValue(false)
        service.fseventRecoverySignal.install {
            ownerRecoverySignaled.set(true)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            callbackReady.signal()
            guard callbackMayProceed.wait(timeout: .now() + 5) == .success else {
                callbackFinished.signal()
                return
            }
            service.markFSEventIDsWrappedAtPublicationPermitForTesting(
                deliveryGeneration: proof.deliveryGeneration
            )
            callbackObservedPublication.set(publicationCompleted.value)
            callbackFinished.signal()
        }
        XCTAssertEqual(callbackReady.wait(timeout: .now() + 5), .success)

        let result = service.withSeededPublicationRecoveryPermitForTesting(
            proof,
            onAcquired: {
                callbackMayProceed.signal()
            },
            body: {
                publicationCompleted.set(true)
                return true
            }
        )
        // Keep the callback teardown bounded even if permit acquisition fails
        // before the interleaving hook is reached.
        callbackMayProceed.signal()
        XCTAssertEqual(result, true)
        XCTAssertEqual(callbackFinished.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(callbackObservedPublication.value)
        XCTAssertTrue(ownerRecoverySignaled.value)
        XCTAssertTrue(service.fseventRecoveryGate.isRequired)

        let finalized = await service.finalizeSeededPublication(proof)
        XCTAssertFalse(finalized, "A post-linearization wrap must route to recovery, not stale publication")
        await service.abortSeededPreparation(initializationID: initializationID)
        service.fseventRecoverySignal.clear()
        await service.stopWatchingForChanges()
    }

    func testSeededPublicationRejectsWrapBeforeActivation() async throws {
        let (service, initializationID) = try await makeSeededServiceReadyForPublication(
            name: "FileSystemSeededWrapBeforeActivation"
        )
        let deliveryGeneration = service.fseventDeliveryBarrier.currentGeneration
        let streamGeneration = await service.fseventStreamGenerationForTesting()
        let ingressGeneration = await service.watcherIngressGenerationForTesting()
        await service.handleFSEventIDsWrappedForTesting(
            streamGeneration: streamGeneration,
            ingressGeneration: ingressGeneration,
            deliveryGeneration: deliveryGeneration
        )

        let proof = await service.activateSeededPublication(initializationID: initializationID)
        XCTAssertNil(proof, "A callback-observed wrap must block seeded activation")
        let recoveryRequired = await service.fseventRecoveryRequiredForTesting()
        XCTAssertTrue(recoveryRequired)
        await service.abortSeededPreparation(initializationID: initializationID)
    }

    func testSeededPublicationFinalizationRejectsWrapAfterActivationBeforePublication() async throws {
        let (service, initializationID) = try await makeSeededServiceReadyForPublication(
            name: "FileSystemSeededWrapBeforeFinalization"
        )
        guard let proof = await service.activateSeededPublication(initializationID: initializationID) else {
            await service.abortSeededPreparation(initializationID: initializationID)
            return XCTFail("Expected a ready seeded service to activate")
        }
        let deliveryGeneration = service.fseventDeliveryBarrier.currentGeneration
        let streamGeneration = await service.fseventStreamGenerationForTesting()
        let ingressGeneration = await service.watcherIngressGenerationForTesting()
        await service.handleFSEventIDsWrappedForTesting(
            streamGeneration: streamGeneration,
            ingressGeneration: ingressGeneration,
            deliveryGeneration: deliveryGeneration
        )

        let activationIsCurrent = await service.seededPublicationActivationIsCurrent(proof)
        XCTAssertFalse(activationIsCurrent)
        let finalized = await service.finalizeSeededPublication(proof)
        XCTAssertFalse(finalized)
        await service.abortSeededPreparation(initializationID: initializationID)
        await service.stopWatchingForChanges()
    }

    private func makeSeededServiceReadyForPublication(
        name: String
    ) async throws -> (FileSystemService, FileSystemSeedInitializationID) {
        let root = try makeTestDirectory(name: name)
        let service = try await FileSystemService(
            path: root.path,
            respectRepoIgnore: false,
            respectCursorignore: false,
            skipSymlinks: true,
            isTestMode: true
        )
        let initializationID = FileSystemSeedInitializationID()
        _ = try await service.startWatchingForSeedPreparation(
            since: FileSystemSeedReplayJournalCut(fseventID: 1),
            initializationID: initializationID
        )
        let preparation = try await service.prepareSeededInventoryForTesting(
            relativeFilePaths: [],
            relativeFolderPaths: [],
            initializationID: initializationID
        )
        try await service.installSeededInventory(preparation)
        let replayCut = try await service.captureSeedReplayAcceptedWatermark(
            initializationID: initializationID
        )
        _ = try await service.flushSeedReplay(
            through: replayCut,
            initializationID: initializationID
        )
        return (service, initializationID)
    }

    private func payload(path: String, eventID: FSEventStreamEventId) -> FSEventCallbackPayload {
        FSEventCallbackPayload(entries: [
            FSEventCallbackEntry(
                path: path,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                id: eventID
            )
        ])
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

private final class LivenessLockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}
