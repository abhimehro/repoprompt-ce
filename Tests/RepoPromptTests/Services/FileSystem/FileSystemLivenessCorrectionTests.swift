import CoreServices
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

    func testWrappedCutCannotUseOldHighWatermarkAndOnlyFreshGenerationRecovers() async {
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
        let oldWatermarkDeliveredToReplacement = await barrier.waitUntilDelivered(
            5,
            generation: newGeneration!
        )
        XCTAssertFalse(oldWatermarkDeliveredToReplacement)

        barrier.recordDelivered(eventIDs: [5], generation: newGeneration!)
        let freshGenerationDelivered = await barrier.waitUntilDelivered(
            5,
            generation: newGeneration!
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

    private func payload(path: String, eventID: FSEventStreamEventId) -> FSEventCallbackPayload {
        FSEventCallbackPayload(entries: [
            FSEventCallbackEntry(
                path: path,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                id: eventID
            )
        ])
    }
}
