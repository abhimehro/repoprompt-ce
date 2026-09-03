@testable import RepoPromptApp
import RepoPromptDomainRuntime
import XCTest

final class MCPReadMutationPathContractTests: XCTestCase {
    func testApplyEditsMissingTargetPolicyFailsClosedAcrossProjectedNamespace() {
        let addressedRoot = WorkspaceRootRef(
            id: UUID(),
            name: "Addressed",
            fullPath: "/tmp/addressed"
        )
        let peerRoot = WorkspaceRootRef(
            id: UUID(),
            name: "Peer",
            fullPath: "/tmp/peer"
        )
        let unavailablePhysicalRoot = WorkspaceRootRef(
            id: UUID(),
            name: "Projected",
            fullPath: "/tmp/missing-worktree"
        )
        let namespace = WorkspaceExactFileNamespace(rootBindings: [
            .init(
                lookupRoot: unavailablePhysicalRoot,
                lookupRole: .projectedPhysical,
                clientRoots: [addressedRoot],
                preferredClientRoot: addressedRoot
            ),
            .init(
                lookupRoot: peerRoot,
                lookupRole: .canonical,
                clientRoots: [peerRoot],
                preferredClientRoot: peerRoot
            )
        ])
        let displayAlias = ClientPathFormatter.nonAbsoluteRootAlias(
            root: addressedRoot,
            visibleRoots: namespace.clientRoots
        )

        let cases: [(label: String, input: WorkspaceExactFileInput, expected: Bool)] = [
            ("absolute", .absolute("/tmp/addressed/New.swift"), true),
            ("explicit root", .explicitRoot(alias: displayAlias, relativePath: "New.swift"), true),
            ("projected display alias", .relative("\(displayAlias)/New.swift"), true),
            ("bare relative", .relative("New.swift"), false),
            ("literal subdirectory", .relative("unknown/New.swift"), false)
        ]

        for testCase in cases {
            XCTAssertEqual(
                MCPApplyEditsMissingTargetPolicy.requiresExistingFile(
                    testCase.input,
                    namespace: namespace
                ),
                testCase.expected,
                testCase.label
            )
        }
    }

    func testApplyEditsMissingTargetPolicyBlocksQualifiedDiskCreationAndAllowsBareCreate() async throws {
        let parent = try makeTemporaryDirectory(name: "ApplyEditsMissingTargetDiskPolicy")
        let physicalRootURL = parent.appendingPathComponent("Physical", isDirectory: true)
        let logicalRootURL = parent.appendingPathComponent("Logical", isDirectory: true)
        try FileManager.default.createDirectory(at: physicalRootURL, withIntermediateDirectories: true)

        let store = WorkspaceFileContextStore()
        let physicalRootRecord = try await store.loadRoot(path: physicalRootURL.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let physicalRoot = try XCTUnwrap(roots.first(where: { $0.id == physicalRootRecord.id }))
        let logicalRoot = WorkspaceRootRef(id: UUID(), name: "Logical", fullPath: logicalRootURL.path)
        let namespace = WorkspaceExactFileNamespace(rootBindings: [
            .init(
                lookupRoot: physicalRoot,
                lookupRole: .projectedPhysical,
                clientRoots: [logicalRoot],
                preferredClientRoot: logicalRoot
            )
        ])
        let displayAlias = ClientPathFormatter.nonAbsoluteRootAlias(
            root: logicalRoot,
            visibleRoots: namespace.clientRoots
        )
        let qualifiedInputs: [WorkspaceExactFileInput] = [
            .absolute(logicalRootURL.appendingPathComponent("Qualified.swift").path),
            .explicitRoot(alias: displayAlias, relativePath: "Qualified.swift"),
            .relative("\(displayAlias)/Qualified.swift")
        ]
        for input in qualifiedInputs {
            XCTAssertTrue(MCPApplyEditsMissingTargetPolicy.requiresExistingFile(input, namespace: namespace))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: physicalRootURL.appendingPathComponent("Qualified.swift").path))

        let bareInput = WorkspaceExactFileInput.relative("Created.swift")
        XCTAssertFalse(MCPApplyEditsMissingTargetPolicy.requiresExistingFile(bareInput, namespace: namespace))
        let host = WorkspaceFileEditHost(
            store: store,
            target: .create(path: "Created.swift"),
            lookupRootScope: .visibleWorkspace,
            createPathResolutionPolicy: .canonicalAliasFirst,
            selectCreatedFiles: false
        )
        let result = try await ApplyEditsService(engine: .default, host: host).run(
            ApplyEditsRequest(
                path: "Created.swift",
                mode: .rewrite(newText: "created\n", onMissing: .create),
                verbose: false
            )
        )
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(
            try String(contentsOf: physicalRootURL.appendingPathComponent("Created.swift"), encoding: .utf8),
            "created\n"
        )
    }

    #if DEBUG
        func testQualifiedResolutionSkipsPeerProbeWhileBareRelativeClassifiesNamespace() async throws {
            let parent = try makeTemporaryDirectory(name: "QualifiedPeerIsolation")
            let addressedRootURL = parent.appendingPathComponent("Addressed", isDirectory: true)
            let peerRootURL = parent.appendingPathComponent("Peer", isDirectory: true)
            let addressedFile = addressedRootURL.appendingPathComponent("Target.swift")
            try write("addressed\n", to: addressedFile)
            try write("peer\n", to: peerRootURL.appendingPathComponent("Peer.swift"))

            let store = WorkspaceFileContextStore()
            let addressedRoot = try await store.loadRoot(path: addressedRootURL.path)
            let peerRoot = try await store.loadRoot(path: peerRootURL.path)
            let roots = await store.rootRefs(scope: .visibleWorkspace)
            let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
            let peerSerialPosition = try XCTUnwrap(namespace.rootBindings.firstIndex {
                $0.lookupRoot.id == peerRoot.id
            })
            let probe = ExactResolutionPeerProbe()
            addTeardownBlock {
                await store.clearExactFileCandidateProbeGateForTesting()
            }

            await store.setExactFileCandidateProbeGateForTesting(
                purpose: .canonicalCompaction,
                rootID: peerRoot.id,
                serialPosition: peerSerialPosition
            ) {
                await probe.record()
            }
            let qualifiedResolution = try await store.resolveExactExistingWorkspaceFile(
                WorkspaceExactFileInput.parse(addressedFile.path),
                namespace: namespace
            )
            guard case let .matched(qualifiedMatch) = qualifiedResolution else {
                return XCTFail("Expected the qualified target")
            }
            XCTAssertEqual(qualifiedMatch.file.rootID, addressedRoot.id)
            let qualifiedPeerProbeCount = await probe.count
            XCTAssertEqual(qualifiedPeerProbeCount, 0)

            await store.setExactFileCandidateProbeGateForTesting(
                purpose: .bareRelativeNamespaceClassification,
                rootID: peerRoot.id,
                serialPosition: peerSerialPosition
            ) {
                await probe.record()
            }
            let relativeResolution = try await store.resolveExactExistingWorkspaceFile(
                WorkspaceExactFileInput.parse("Target.swift"),
                namespace: namespace
            )
            guard case let .matched(relativeMatch) = relativeResolution else {
                return XCTFail("Expected the unique relative target")
            }
            XCTAssertEqual(relativeMatch.file.id, qualifiedMatch.file.id)
            let relativePeerProbeCount = await probe.count
            XCTAssertEqual(relativePeerProbeCount, 1)
        }

        func testCanonicalCompactionRevalidatesEarlierPeerBeforeReturningBareToken() async throws {
            let parent = try makeTemporaryDirectory(name: "CanonicalCompactionPeerDrift")
            let earlierRootURL = parent.appendingPathComponent("Earlier", isDirectory: true)
            let addressedRootURL = parent.appendingPathComponent("Addressed", isDirectory: true)
            let laterRootURL = parent.appendingPathComponent("Later", isDirectory: true)
            let relativePath = "Target.swift"
            let addressedFileURL = addressedRootURL.appendingPathComponent(relativePath)
            let earlierFileURL = earlierRootURL.appendingPathComponent(relativePath)
            try write("earlier sentinel\n", to: earlierRootURL.appendingPathComponent("Earlier.swift"))
            try write("addressed\n", to: addressedFileURL)
            try write("later sentinel\n", to: laterRootURL.appendingPathComponent("Later.swift"))

            let store = WorkspaceFileContextStore()
            let earlierRoot = try await store.loadRoot(path: earlierRootURL.path)
            let addressedRoot = try await store.loadRoot(path: addressedRootURL.path)
            let laterRoot = try await store.loadRoot(path: laterRootURL.path)
            let roots = await store.rootRefs(scope: .visibleWorkspace)
            let earlierRootRef = try XCTUnwrap(roots.first(where: { $0.id == earlierRoot.id }))
            let addressedRootRef = try XCTUnwrap(roots.first(where: { $0.id == addressedRoot.id }))
            let laterRootRef = try XCTUnwrap(roots.first(where: { $0.id == laterRoot.id }))
            let namespace = WorkspaceExactFileNamespace.identity(roots: [
                earlierRootRef,
                addressedRootRef,
                laterRootRef
            ])
            let laterSerialPosition = try XCTUnwrap(namespace.rootBindings.firstIndex {
                $0.lookupRoot.id == laterRoot.id
            })
            let gate = MCPPathContractReleaseGate(name: "later canonical compaction peer")
            addTeardownBlock {
                gate.release()
                await store.clearExactFileCandidateProbeGateForTesting()
            }
            await store.setExactFileCandidateProbeGateForTesting(
                purpose: .canonicalCompaction,
                rootID: laterRoot.id,
                serialPosition: laterSerialPosition
            ) {
                await gate.enterAndWait()
            }

            let resolutionTask = Task {
                try await store.resolveExactExistingWorkspaceFile(
                    WorkspaceExactFileInput.parse(relativePath),
                    namespace: namespace
                )
            }
            let compactionEntered = await gate.waitUntilEntered()
            XCTAssertTrue(compactionEntered)
            try write("peer duplicate\n", to: earlierFileURL)
            gate.release()

            let resolution = try await resolutionTask.value
            guard case let .matched(match) = resolution else {
                return XCTFail("Expected the addressed record with an explicit replay token, got \(resolution)")
            }
            XCTAssertEqual(match.file.rootID, addressedRoot.id)
            XCTAssertNotEqual(match.canonicalPath, relativePath)
            guard case .explicitRoot = try WorkspaceExactFileInput.parse(match.canonicalPath) else {
                return XCTFail("Expected binding-explicit canonical path, got \(match.canonicalPath)")
            }

            let explicitReplay = try await store.resolveExactExistingWorkspaceFile(
                WorkspaceExactFileInput.parse(match.canonicalPath),
                namespace: namespace
            )
            guard case let .matched(replayedMatch) = explicitReplay else {
                return XCTFail("Expected the explicit replay token to remain resolvable")
            }
            XCTAssertEqual(replayedMatch.file.id, match.file.id)

            let bareReplay = try await store.resolveExactExistingWorkspaceFile(
                WorkspaceExactFileInput.parse(relativePath),
                namespace: namespace
            )
            guard case .issue(.ambiguousRootMatch) = bareReplay else {
                return XCTFail("Expected the drifted bare token to fail closed, got \(bareReplay)")
            }
        }

        @MainActor
        func testExactResolutionLifecycleDiagnosticsRemainPathFreeAcrossQualifiedAndBareFlows() async throws {
            let parent = try makeTemporaryDirectory(name: "ExactResolutionDiagnosticsPrivacy")
            let addressedRootURL = parent.appendingPathComponent("SensitiveAddressedRoot", isDirectory: true)
            let peerRootURL = parent.appendingPathComponent("SensitivePeerRoot", isDirectory: true)
            let existingFilename = "ExistingSecret.swift"
            let materializedFilename = "MaterializedSecret.swift"
            let sensitiveContent = "private diagnostic payload"
            let existingURL = addressedRootURL.appendingPathComponent(existingFilename)
            let materializedURL = addressedRootURL.appendingPathComponent(materializedFilename)
            try write("\(materializedFilename)\n", to: addressedRootURL.appendingPathComponent(".gitignore"))
            try write(sensitiveContent, to: existingURL)
            try write(sensitiveContent, to: materializedURL)
            try write("peer diagnostic payload", to: peerRootURL.appendingPathComponent("PeerSecret.swift"))

            let store = WorkspaceFileContextStore()
            let addressedRoot = try await store.loadRoot(path: addressedRootURL.path)
            let peerRoot = try await store.loadRoot(path: peerRootURL.path)
            addTeardownBlock {
                await store.unloadRoot(id: addressedRoot.id)
                await store.unloadRoot(id: peerRoot.id)
            }
            let namespace = await WorkspaceExactFileNamespace.identity(
                roots: store.rootRefs(scope: .visibleWorkspace)
            )
            let materializedBeforeResolution = await store.file(
                rootID: addressedRoot.id,
                relativePath: materializedFilename
            )
            XCTAssertNil(materializedBeforeResolution)

            EditFlowPerf.resetDebugCaptureForTesting()
            switch EditFlowPerf.beginDebugCapture(label: "exact-resolution-privacy", maxSamples: 200) {
            case .started:
                break
            case .busy:
                return XCTFail("Exact-resolution diagnostics capture should start")
            }
            var didFinishCapture = false
            defer {
                if !didFinishCapture {
                    _ = EditFlowPerf.debugCaptureSnapshot(finish: true)
                }
            }
            let correlation = try XCTUnwrap(EditFlowPerf.makeLifecycleCorrelationIfActive())
            try await EditFlowPerf.$currentLifecycleCorrelation.withValue(correlation) {
                let inputs = try [
                    WorkspaceExactFileInput.parse(existingURL.path),
                    WorkspaceExactFileInput.parse(materializedURL.path),
                    WorkspaceExactFileInput.parse(existingFilename)
                ]
                for input in inputs {
                    let resolution = try await store.resolveExactExistingWorkspaceFile(
                        input,
                        namespace: namespace
                    )
                    guard case .matched = resolution else {
                        XCTFail("Expected exact resolution for \(input.renderedPath), got \(resolution)")
                        continue
                    }
                }
            }

            let events = EditFlowPerf.debugCaptureSnapshot(finish: true).lifecycleEvents.filter {
                $0.eventName == "WorkspaceExactResolution.Checkpoint"
            }
            didFinishCapture = true
            XCTAssertFalse(events.isEmpty)
            for purpose in [
                "qualifiedTargetValidation",
                "explicitMaterialization",
                "bareRelativeNamespaceClassification",
                "canonicalCompaction"
            ] {
                XCTAssertTrue(events.contains {
                    $0.sanitizedDimensions.contains("purpose=\(purpose)")
                }, "Missing exact-resolution diagnostics for \(purpose)")
            }

            let forbiddenFragments = [
                addressedRootURL.path,
                peerRootURL.path,
                existingFilename,
                materializedFilename,
                sensitiveContent,
                "SensitiveAddressedRoot",
                "SensitivePeerRoot",
                "diagnostic",
                "payload"
            ]
            for event in events {
                XCTAssertFalse(event.sanitizedDimensions.contains("/"), event.sanitizedDimensions)
                for fragment in forbiddenFragments {
                    XCTAssertFalse(event.sanitizedDimensions.contains(fragment), event.sanitizedDimensions)
                }
            }
        }

        func testUnloadReloadDuringCatalogValidationCannotReturnStaleRecord() async throws {
            let rootURL = try makeTemporaryDirectory(name: "CatalogValidationLifetime")
            let targetURL = rootURL.appendingPathComponent("Target.swift")
            try write("original\n", to: targetURL)

            let store = WorkspaceFileContextStore()
            let originalRoot = try await store.loadRoot(path: rootURL.path)
            let originalFile = await store.file(rootID: originalRoot.id, relativePath: "Target.swift")
            let staleFile = try XCTUnwrap(originalFile)
            let namespace = await WorkspaceExactFileNamespace.identity(
                roots: store.rootRefs(scope: .visibleWorkspace)
            )
            let gate = MCPPathContractReleaseGate(name: "exact catalog validation")
            addTeardownBlock {
                gate.release()
                await store.clearExactFileCandidateProbeGateForTesting()
            }
            await store.setExactFileSuspensionGateForTesting(
                point: .catalogValidation,
                rootID: originalRoot.id
            ) {
                await gate.enterAndWait()
            }

            let resolutionTask = Task {
                try await store.resolveExactExistingWorkspaceFile(
                    WorkspaceExactFileInput.parse(targetURL.path),
                    namespace: namespace
                )
            }
            let entered = await gate.waitUntilEntered()
            XCTAssertTrue(entered)
            await store.unloadRoot(id: originalRoot.id)
            let replacementRoot = try await store.loadRoot(path: rootURL.path)
            gate.release()

            let resolution = try await resolutionTask.value
            guard case .issue(.unresolved) = resolution else {
                return XCTFail("Expected unavailable binding after root replacement, got \(resolution)")
            }
            XCTAssertNotEqual(replacementRoot.id, originalRoot.id)
            let staleCatalogRecord = await store.file(
                rootID: originalRoot.id,
                relativePath: staleFile.standardizedRelativePath
            )
            XCTAssertNil(staleCatalogRecord)
        }

        @MainActor
        func testSameRootIDReplacementAfterCatalogValidationFailsClosed() async throws {
            let rootURL = try makeTemporaryDirectory(name: "CatalogValidationSameRootReplacement")
            let targetURL = rootURL.appendingPathComponent("Target.swift")
            try write("original\n", to: targetURL)

            let store = WorkspaceFileContextStore()
            let root = try await store.loadRoot(path: rootURL.path)
            let loadedRecord = await store.file(rootID: root.id, relativePath: "Target.swift")
            let originalRecord = try XCTUnwrap(loadedRecord)
            let replacementService = try await FileSystemService(path: rootURL.path)
            let namespace = await WorkspaceExactFileNamespace.identity(
                roots: store.rootRefs(scope: .visibleWorkspace)
            )
            let gate = MCPPathContractReleaseGate(name: "validated catalog result")
            addTeardownBlock {
                gate.release()
                await store.clearExactFileCandidateProbeGateForTesting()
            }
            await store.setExactFileSuspensionGateForTesting(
                point: .catalogValidationResult,
                rootID: root.id
            ) {
                await gate.enterAndWait()
            }

            EditFlowPerf.resetDebugCaptureForTesting()
            switch EditFlowPerf.beginDebugCapture(label: "catalog-validation-replacement", maxSamples: 40) {
            case .started:
                break
            case .busy:
                return XCTFail("Catalog validation diagnostics capture should start")
            }
            var didFinishCapture = false
            defer {
                if !didFinishCapture {
                    _ = EditFlowPerf.debugCaptureSnapshot(finish: true)
                }
            }
            let correlation = try XCTUnwrap(EditFlowPerf.makeLifecycleCorrelationIfActive())
            let resolutionTask = Task {
                try await EditFlowPerf.$currentLifecycleCorrelation.withValue(correlation) {
                    try await store.resolveExactExistingWorkspaceFile(
                        WorkspaceExactFileInput.parse(targetURL.path),
                        namespace: namespace
                    )
                }
            }
            let validationResultEntered = await gate.waitUntilEntered()
            XCTAssertTrue(validationResultEntered)
            let replacementLifetimeID = await store.replaceRootLifetimeAndServiceKeepingCatalogForTesting(
                rootID: root.id,
                service: replacementService
            )
            XCTAssertNotNil(replacementLifetimeID)
            gate.release()

            let resolution = try await resolutionTask.value
            guard case .issue(.unresolved) = resolution else {
                return XCTFail("Expected same-root-ID epoch replacement to invalidate the validated record")
            }
            let preservedRecord = await store.file(rootID: root.id, relativePath: "Target.swift")
            XCTAssertEqual(preservedRecord?.id, originalRecord.id)

            let probeEvents = EditFlowPerf.debugCaptureSnapshot(finish: true).lifecycleEvents.filter {
                $0.eventName == "WorkspaceExactResolution.Checkpoint"
                    && $0.sanitizedDimensions.contains("purpose=qualifiedTargetValidation")
                    && (
                        $0.sanitizedDimensions.contains("status=bindingProbeBegan")
                            || $0.sanitizedDimensions.contains("status=bindingProbeEnded")
                    )
            }
            didFinishCapture = true
            XCTAssertEqual(probeEvents.count(where: {
                $0.sanitizedDimensions.contains("status=bindingProbeBegan")
            }), 1)
            let terminalEvents = probeEvents.filter {
                $0.sanitizedDimensions.contains("status=bindingProbeEnded")
            }
            XCTAssertEqual(terminalEvents.count, 1)
            XCTAssertTrue(terminalEvents.allSatisfy {
                $0.sanitizedDimensions.contains("outcome=unavailable")
            })
        }

        @MainActor
        func testCancellationAfterEligibilityBalancesBindingProbeDiagnostics() async throws {
            let rootURL = try makeTemporaryDirectory(name: "CancelledEligibilityDiagnostics")
            let targetURL = rootURL.appendingPathComponent("Missing.swift")
            let store = WorkspaceFileContextStore()
            let root = try await store.loadRoot(path: rootURL.path)
            let namespace = await WorkspaceExactFileNamespace.identity(
                roots: store.rootRefs(scope: .visibleWorkspace)
            )
            let gate = MCPPathContractReleaseGate(name: "cancelled exact eligibility")
            addTeardownBlock {
                gate.release()
                await store.clearExactFileCandidateProbeGateForTesting()
            }
            await store.setExactFileSuspensionGateForTesting(
                point: .candidateEligibility,
                rootID: root.id
            ) {
                await gate.enterAndWaitIgnoringCancellationUntilRelease()
            }

            EditFlowPerf.resetDebugCaptureForTesting()
            switch EditFlowPerf.beginDebugCapture(label: "cancelled-eligibility-diagnostics", maxSamples: 40) {
            case .started:
                break
            case .busy:
                return XCTFail("Cancellation diagnostics capture should start")
            }
            var didFinishCapture = false
            defer {
                if !didFinishCapture {
                    _ = EditFlowPerf.debugCaptureSnapshot(finish: true)
                }
            }
            let correlation = try XCTUnwrap(EditFlowPerf.makeLifecycleCorrelationIfActive())
            let resolutionTask = Task {
                try await EditFlowPerf.$currentLifecycleCorrelation.withValue(correlation) {
                    try await store.resolveExactExistingWorkspaceFile(
                        WorkspaceExactFileInput.parse(targetURL.path),
                        namespace: namespace
                    )
                }
            }
            let eligibilityEntered = await gate.waitUntilEntered()
            XCTAssertTrue(eligibilityEntered)
            resolutionTask.cancel()
            gate.release()

            do {
                _ = try await resolutionTask.value
                XCTFail("Expected exact resolution cancellation")
            } catch is CancellationError {}

            let probeEvents = EditFlowPerf.debugCaptureSnapshot(finish: true).lifecycleEvents.filter {
                $0.eventName == "WorkspaceExactResolution.Checkpoint"
                    && $0.sanitizedDimensions.contains("purpose=qualifiedTargetValidation")
                    && (
                        $0.sanitizedDimensions.contains("status=bindingProbeBegan")
                            || $0.sanitizedDimensions.contains("status=bindingProbeEnded")
                    )
            }
            didFinishCapture = true
            let beganEvents = probeEvents.filter {
                $0.sanitizedDimensions.contains("status=bindingProbeBegan")
            }
            let endedEvents = probeEvents.filter {
                $0.sanitizedDimensions.contains("status=bindingProbeEnded")
            }
            XCTAssertEqual(beganEvents.count, 1)
            XCTAssertEqual(endedEvents.count, beganEvents.count)
            XCTAssertTrue(endedEvents.allSatisfy {
                $0.sanitizedDimensions.contains("outcome=cancelled")
            })
        }

        func testUnloadReloadDuringEligibilityCannotMaterializeReplacementLifetime() async throws {
            let rootURL = try makeTemporaryDirectory(name: "EligibilityLifetime")
            let targetURL = rootURL.appendingPathComponent("Target.swift")
            let store = WorkspaceFileContextStore()
            let originalRoot = try await store.loadRoot(path: rootURL.path)
            let namespace = await WorkspaceExactFileNamespace.identity(
                roots: store.rootRefs(scope: .visibleWorkspace)
            )
            try write("replacement lifetime\n", to: targetURL)
            let gate = MCPPathContractReleaseGate(name: "exact candidate eligibility")
            addTeardownBlock {
                gate.release()
                await store.clearExactFileCandidateProbeGateForTesting()
            }
            await store.setExactFileSuspensionGateForTesting(
                point: .candidateEligibility,
                rootID: originalRoot.id
            ) {
                await gate.enterAndWait()
            }

            let resolutionTask = Task {
                try await store.resolveExactExistingWorkspaceFile(
                    WorkspaceExactFileInput.parse(targetURL.path),
                    namespace: namespace
                )
            }
            let entered = await gate.waitUntilEntered()
            XCTAssertTrue(entered)
            await store.unloadRoot(id: originalRoot.id)
            let replacementRoot = try await store.loadRoot(path: rootURL.path)
            gate.release()

            let resolution = try await resolutionTask.value
            guard case .issue(.unresolved) = resolution else {
                return XCTFail("Expected unavailable binding after eligibility raced replacement, got \(resolution)")
            }
            XCTAssertNotEqual(replacementRoot.id, originalRoot.id)
            let replacementFile = await store.file(rootID: replacementRoot.id, relativePath: "Target.swift")
            XCTAssertEqual(replacementFile?.rootID, replacementRoot.id)
        }

        func testRootDisappearanceDuringMissingFileCleanupFailsClosed() async throws {
            let rootURL = try makeTemporaryDirectory(name: "MissingCleanupLifetime")
            let targetURL = rootURL.appendingPathComponent("Missing.swift")
            let store = WorkspaceFileContextStore()
            let originalRoot = try await store.loadRoot(path: rootURL.path)
            let namespace = await WorkspaceExactFileNamespace.identity(
                roots: store.rootRefs(scope: .visibleWorkspace)
            )
            let gate = MCPPathContractReleaseGate(name: "exact missing-file cleanup")
            addTeardownBlock {
                gate.release()
                await store.clearExactFileCandidateProbeGateForTesting()
            }
            await store.setExactFileSuspensionGateForTesting(
                point: .candidateMissingFilePrune,
                rootID: originalRoot.id
            ) {
                await gate.enterAndWait()
            }

            let resolutionTask = Task {
                try await store.resolveExactExistingWorkspaceFile(
                    WorkspaceExactFileInput.parse(targetURL.path),
                    namespace: namespace
                )
            }
            let entered = await gate.waitUntilEntered()
            XCTAssertTrue(entered)
            await store.unloadRoot(id: originalRoot.id)
            gate.release()

            let resolution = try await resolutionTask.value
            guard case .issue(.unresolved) = resolution else {
                return XCTFail("Expected unavailable binding after root disappearance, got \(resolution)")
            }
            let staleCatalogRecord = await store.file(rootID: originalRoot.id, relativePath: "Missing.swift")
            XCTAssertNil(staleCatalogRecord)
        }

        func testCancellationDuringExplicitRegistrationDoesNotPublishRecord() async throws {
            let rootURL = try makeTemporaryDirectory(name: "CancelledExactMaterialization")
            let targetURL = rootURL.appendingPathComponent("Target.swift")
            let store = WorkspaceFileContextStore()
            let root = try await store.loadRoot(path: rootURL.path)
            let namespace = await WorkspaceExactFileNamespace.identity(
                roots: store.rootRefs(scope: .visibleWorkspace)
            )
            try write("late target\n", to: targetURL)
            let gate = MCPPathContractReleaseGate(name: "explicit managed registration")
            addTeardownBlock {
                gate.release()
                await store.clearExactFileCandidateProbeGateForTesting()
            }
            await store.setExactFileSuspensionGateForTesting(
                point: .explicitManagedRegistration,
                rootID: root.id
            ) {
                await gate.enterAndWaitIgnoringCancellationUntilRelease()
            }

            let resolutionTask = Task {
                try await store.resolveExactExistingWorkspaceFile(
                    WorkspaceExactFileInput.parse(targetURL.path),
                    namespace: namespace
                )
            }
            let entered = await gate.waitUntilEntered()
            XCTAssertTrue(entered)
            resolutionTask.cancel()
            gate.release()

            do {
                _ = try await resolutionTask.value
                XCTFail("Expected exact materialization cancellation")
            } catch is CancellationError {
                let publishedRecord = await store.file(rootID: root.id, relativePath: "Target.swift")
                XCTAssertNil(publishedRecord)
            }
        }

        func testDirectoryClassificationReflectsPostPrunePathState() async throws {
            let rootURL = try makeTemporaryDirectory(name: "PostPruneDirectoryClassification")
            let store = WorkspaceFileContextStore()
            let root = try await store.loadRoot(path: rootURL.path)
            let roots = await store.rootRefs(scope: .visibleWorkspace)
            let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
            let createdDirectoryURL = rootURL.appendingPathComponent("CreatedDirectory", isDirectory: true)
            let removedDirectoryURL = rootURL.appendingPathComponent("RemovedDirectory", isDirectory: true)
            let creationGate = MCPPathContractReleaseGate(name: "missing path becomes directory")
            let removalGate = MCPPathContractReleaseGate(name: "directory becomes missing")
            addTeardownBlock {
                creationGate.release()
                removalGate.release()
                await store.clearExactFileCandidateProbeGateForTesting()
            }

            await store.setExactFileSuspensionGateForTesting(
                point: .missingFilePruneFence,
                rootID: root.id
            ) {
                await creationGate.enterAndWait()
            }
            let creationResolutionTask = Task {
                try await store.resolveExactExistingWorkspaceFile(
                    WorkspaceExactFileInput.parse(createdDirectoryURL.path),
                    namespace: namespace
                )
            }
            let creationProbeEntered = await creationGate.waitUntilEntered()
            XCTAssertTrue(creationProbeEntered)
            try FileManager.default.createDirectory(at: createdDirectoryURL, withIntermediateDirectories: true)
            creationGate.release()
            let creationResolution = try await creationResolutionTask.value
            guard case let .directory(match) = creationResolution else {
                return XCTFail("Expected the post-fence directory, got \(creationResolution)")
            }
            XCTAssertEqual(match.relativePath, "CreatedDirectory")

            await store.clearExactFileCandidateProbeGateForTesting()
            try FileManager.default.createDirectory(at: removedDirectoryURL, withIntermediateDirectories: true)
            await store.setExactFileSuspensionGateForTesting(
                point: .missingFilePruneFence,
                rootID: root.id
            ) {
                await removalGate.enterAndWait()
            }
            let removalResolutionTask = Task {
                try await store.resolveExactExistingWorkspaceFile(
                    WorkspaceExactFileInput.parse(removedDirectoryURL.path),
                    namespace: namespace
                )
            }
            let removalProbeEntered = await removalGate.waitUntilEntered()
            XCTAssertTrue(removalProbeEntered)
            try FileManager.default.removeItem(at: removedDirectoryURL)
            removalGate.release()
            let removalResolution = try await removalResolutionTask.value
            guard case .claimedMissing = removalResolution else {
                return XCTFail("Expected the removed post-fence directory to be missing, got \(removalResolution)")
            }
        }

        func testRecreatedFileDuringMissingPruneRetainsCurrentCatalogRecord() async throws {
            let rootURL = try makeTemporaryDirectory(name: "RecreatedFileDuringPrune")
            let targetURL = rootURL.appendingPathComponent("Target.swift")
            try write("original\n", to: targetURL)

            let store = WorkspaceFileContextStore()
            let root = try await store.loadRoot(path: rootURL.path)
            let originalRecord = await store.file(rootID: root.id, relativePath: "Target.swift")
            let expectedRecord = try XCTUnwrap(originalRecord)
            let namespace = await WorkspaceExactFileNamespace.identity(
                roots: store.rootRefs(scope: .visibleWorkspace)
            )
            try FileManager.default.removeItem(at: targetURL)
            let gate = MCPPathContractReleaseGate(name: "missing-file prune fence")
            addTeardownBlock {
                gate.release()
                await store.clearExactFileCandidateProbeGateForTesting()
            }
            await store.setExactFileSuspensionGateForTesting(
                point: .missingFilePruneFence,
                rootID: root.id
            ) {
                await gate.enterAndWait()
            }

            let resolutionTask = Task {
                try await store.resolveExactExistingWorkspaceFile(
                    WorkspaceExactFileInput.parse(targetURL.path),
                    namespace: namespace
                )
            }
            let entered = await gate.waitUntilEntered()
            XCTAssertTrue(entered)
            try write("recreated\n", to: targetURL)
            gate.release()

            let resolution = try await resolutionTask.value
            guard case .issue(.unresolved) = resolution else {
                return XCTFail("Expected recreated target to invalidate the stale missing classification")
            }
            let currentRecord = await store.file(rootID: root.id, relativePath: "Target.swift")
            XCTAssertEqual(currentRecord?.id, expectedRecord.id)
            XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "recreated\n")
        }

        func testCancellationDuringCodemapCleanupSettlesAndAllowsSubsequentMaterialization() async throws {
            let rootURL = try makeTemporaryDirectory(name: "CancelledCodemapCleanup")
            let targetURL = rootURL.appendingPathComponent("Target.swift")
            let followupURL = rootURL.appendingPathComponent("Followup.swift")
            let store = WorkspaceFileContextStore()
            let root = try await store.loadRoot(path: rootURL.path)
            let namespace = await WorkspaceExactFileNamespace.identity(
                roots: store.rootRefs(scope: .visibleWorkspace)
            )
            try write("target\n", to: targetURL)
            let cleanupWaitGate = MCPPathContractReleaseGate(name: "exact cleanup wait boundary")
            let cleanupGate = MCPPathContractReleaseGate(name: "store-owned codemap cleanup")
            let cancellationCompletion = MCPPathContractReleaseGate(name: "cancelled materialization completion")
            let followupCompletion = MCPPathContractReleaseGate(name: "followup materialization completion")
            addTeardownBlock {
                cleanupWaitGate.release()
                cleanupGate.release()
                cancellationCompletion.release()
                followupCompletion.release()
                await store.clearExactFileCandidateProbeGateForTesting()
            }
            await store.setExactFileSuspensionGateForTesting(
                point: .codemapCleanupWait,
                rootID: root.id
            ) {
                await cleanupWaitGate.enterAndWaitIgnoringCancellationUntilRelease()
            }

            let resolutionTask = Task {
                try await store.resolveExactExistingWorkspaceFile(
                    WorkspaceExactFileInput.parse(targetURL.path),
                    namespace: namespace
                )
            }
            let cleanupWaitEntered = await cleanupWaitGate.waitUntilEntered()
            XCTAssertTrue(cleanupWaitEntered)
            let installedCleanupFlight = await store.installCodemapCleanupFlightForTesting(
                rootID: root.id
            ) {
                await cleanupGate.enterAndWait()
            }
            XCTAssertTrue(installedCleanupFlight)
            let cleanupFlightEntered = await cleanupGate.waitUntilEntered()
            XCTAssertTrue(cleanupFlightEntered)
            cleanupWaitGate.release()
            try await MCPPathContractAsyncWait.waitUntil("exact cleanup waiter registration", timeout: 10) {
                await store.codemapCleanupWaiterCountForTesting(rootID: root.id) == 1
            }
            let eventsBeforeCancellation = await store.codemapGraphIndexBuildStoreEventsForTesting(
                rootID: root.id
            )
            let lastEventOrdinalBeforeCancellation = eventsBeforeCancellation.map(\.ordinal).max() ?? 0
            resolutionTask.cancel()
            let cancellationObserver = Task {
                let wasCancelled: Bool
                do {
                    _ = try await resolutionTask.value
                    wasCancelled = false
                } catch is CancellationError {
                    wasCancelled = true
                } catch {
                    XCTFail("Expected cancellation, got \(error)")
                    wasCancelled = false
                }
                await cancellationCompletion.enterAndWait()
                return wasCancelled
            }
            let cancellationSettled = await cancellationCompletion.waitUntilEntered()
            XCTAssertTrue(cancellationSettled)
            if !cancellationSettled {
                cleanupGate.release()
            }
            cancellationCompletion.release()
            let wasCancelled = await cancellationObserver.value
            XCTAssertTrue(wasCancelled)
            let retainedCleanupWaiterCount = await store.codemapCleanupWaiterCountForTesting(rootID: root.id)
            XCTAssertEqual(retainedCleanupWaiterCount, 0)
            let firstMaterializedRecord = await store.file(rootID: root.id, relativePath: "Target.swift")
            XCTAssertNotNil(firstMaterializedRecord)

            let eventsBeforeCleanupSettlement = await store.codemapGraphIndexBuildStoreEventsForTesting(
                rootID: root.id
            )
            let lastEventOrdinalBeforeCleanupSettlement = eventsBeforeCleanupSettlement.map(\.ordinal).max() ?? 0
            cleanupGate.release()
            XCTAssertGreaterThanOrEqual(lastEventOrdinalBeforeCleanupSettlement, lastEventOrdinalBeforeCancellation)
            try await MCPPathContractAsyncWait.waitUntil("cancelled materialization codemap reschedule", timeout: 10) {
                let events = await store.codemapGraphIndexBuildStoreEventsForTesting(rootID: root.id)
                return events.contains {
                    $0.ordinal > lastEventOrdinalBeforeCleanupSettlement && $0.kind == .scheduled
                }
            }
            try write("followup\n", to: followupURL)
            let followupTask = Task {
                let resolution = try await store.resolveExactExistingWorkspaceFile(
                    WorkspaceExactFileInput.parse(followupURL.path),
                    namespace: namespace
                )
                await followupCompletion.enterAndWait()
                return resolution
            }
            let followupSettled = await followupCompletion.waitUntilEntered()
            XCTAssertTrue(followupSettled)
            followupCompletion.release()
            let followupResolution = try await followupTask.value
            guard case let .matched(match) = followupResolution else {
                return XCTFail("Expected a subsequent materialization after cancellation settlement")
            }
            XCTAssertEqual(match.file.standardizedFullPath, StandardizedPath.absolute(followupURL.path))
        }
    #endif

    func testQualifiedMultiRootTokensReplayOnlyToAddressedRecordAndFailClosedAcrossRootLifetime() async throws {
        let parent = try makeTemporaryDirectory(name: "QualifiedReplayIdentity")
        let rootA = parent.appendingPathComponent("A", isDirectory: true)
        let rootB = parent.appendingPathComponent("B", isDirectory: true)
        let fileA = rootA.appendingPathComponent("Target.swift")
        let fileB = rootB.appendingPathComponent("Target.swift")
        try write("addressed token\n", to: fileA)
        try write("peer token\n", to: fileB)

        let store = WorkspaceFileContextStore()
        let recordA = try await store.loadRoot(path: rootA.path)
        _ = try await store.loadRoot(path: rootB.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceExactFileNamespace.identity(roots: roots)

        let absoluteResolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(fileA.path),
            namespace: namespace
        )
        guard case let .matched(absoluteMatch) = absoluteResolution else {
            return XCTFail("Expected the absolute target")
        }
        guard case let .explicitRoot(alias, relativePath) = try WorkspaceExactFileInput.parse(
            absoluteMatch.canonicalPath
        ) else {
            return XCTFail("Expected a binding-explicit canonical token")
        }
        XCTAssertEqual(relativePath, "Target.swift")

        let explicitResolution = try await store.resolveExactExistingWorkspaceFile(
            .explicitRoot(alias: alias, relativePath: relativePath),
            namespace: namespace
        )
        guard case let .matched(explicitMatch) = explicitResolution else {
            return XCTFail("Expected the explicit token to replay")
        }
        XCTAssertEqual(explicitMatch.file.id, absoluteMatch.file.id)
        XCTAssertEqual(explicitMatch.canonicalPath, absoluteMatch.canonicalPath)

        let host = WorkspaceFileEditHost(store: store, target: .existing(explicitMatch.file))
        _ = try await ApplyEditsService(engine: .default, host: host).run(
            ApplyEditsRequest(
                path: absoluteMatch.canonicalPath,
                mode: .single(search: "addressed", replace: "edited", replaceAll: false),
                verbose: true
            )
        )
        XCTAssertEqual(try String(contentsOf: fileA, encoding: .utf8), "edited token\n")
        XCTAssertEqual(try String(contentsOf: fileB, encoding: .utf8), "peer token\n")

        await store.unloadRoot(id: recordA.id)
        let unloadedNamespace = await WorkspaceExactFileNamespace.identity(
            roots: store.rootRefs(scope: .visibleWorkspace)
        )
        let unloadedReplay = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(absoluteMatch.canonicalPath),
            namespace: unloadedNamespace
        )
        if case let .matched(unloadedMatch) = unloadedReplay {
            XCTFail("An unloaded qualified token selected record \(unloadedMatch.file.id)")
        }

        let replacementA = try await store.loadRoot(path: rootA.path)
        XCTAssertNotEqual(replacementA.id, recordA.id)
        let replacementNamespace = await WorkspaceExactFileNamespace.identity(
            roots: store.rootRefs(scope: .visibleWorkspace)
        )
        let staleReplay = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(absoluteMatch.canonicalPath),
            namespace: replacementNamespace
        )
        if case let .matched(staleMatch) = staleReplay {
            XCTFail("A stale qualified token selected record \(staleMatch.file.id)")
        }
    }

    func testQualifiedSingleBindingAliasLookingPathUsesExplicitToken() async throws {
        let parent = try makeTemporaryDirectory(name: "QualifiedAliasLookingPath")
        let root = parent.appendingPathComponent("mimic", isDirectory: true)
        let nested = root.appendingPathComponent("mimic/session.py")
        try write("nested token\n", to: nested)

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
        let resolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(nested.path),
            namespace: namespace
        )
        guard case let .matched(match) = resolution else {
            return XCTFail("Expected the qualified nested target")
        }
        guard case .explicitRoot = try WorkspaceExactFileInput.parse(match.canonicalPath) else {
            return XCTFail("Expected an explicit token for an alias-looking relative component")
        }
        let replay = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(match.canonicalPath),
            namespace: namespace
        )
        guard case let .matched(replayMatch) = replay else {
            return XCTFail("Expected the alias-looking token to replay")
        }
        XCTAssertEqual(replayMatch.file.id, match.file.id)
    }

    func testReadDisplayPathAppliesEditsToLiteralCollisionFile() async throws {
        let parent = try makeTemporaryDirectory(name: "LiteralCollision")
        let root = parent.appendingPathComponent("mimic", isDirectory: true)
        let rootFile = root.appendingPathComponent("session.py")
        let nestedFile = root.appendingPathComponent("mimic/session.py")
        try write("root token\n", to: rootFile)
        try write("nested token\n", to: nestedFile)

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceLookupContext.visibleWorkspace.exactFileNamespace(storeRoots: roots)
        let readableService = WorkspaceReadableFileService(store: store)

        let nestedResolution = try await readableService.resolveReadFileRequest(
            WorkspaceExactFileInput.parse("mimic/session.py"),
            rootScope: .visibleWorkspace,
            rootRefs: roots,
            namespace: namespace
        )
        guard case let .workspace(match) = nestedResolution else {
            return XCTFail("Expected the literal nested file")
        }
        XCTAssertTrue(match.canonicalPath.hasSuffix("//mimic/session.py"))
        let applyResolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(match.canonicalPath),
            namespace: namespace
        )
        guard case let .matched(applyMatch) = applyResolution else {
            return XCTFail("Expected the read path to resolve for apply_edits")
        }
        XCTAssertEqual(applyMatch.file.id, match.file.id)

        let host = WorkspaceFileEditHost(
            store: store,
            target: .existing(applyMatch.file),
            lookupRootScope: .visibleWorkspace,
            createPathResolutionPolicy: .canonicalAliasFirst,
            selectCreatedFiles: false
        )
        let result = try await ApplyEditsService(engine: .default, host: host).run(
            ApplyEditsRequest(
                path: match.canonicalPath,
                mode: .single(search: "nested", replace: "edited", replaceAll: false),
                verbose: true
            )
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(try String(contentsOf: rootFile, encoding: .utf8), "root token\n")
        XCTAssertEqual(try String(contentsOf: nestedFile, encoding: .utf8), "edited token\n")
    }

    func testReadDisplayPathAppliesEditsToRootFileBesideLiteralCollision() async throws {
        let parent = try makeTemporaryDirectory(name: "RootCollision")
        let root = parent.appendingPathComponent("mimic", isDirectory: true)
        let rootFile = root.appendingPathComponent("session.py")
        let nestedFile = root.appendingPathComponent("mimic/session.py")
        try write("root token\n", to: rootFile)
        try write("nested token\n", to: nestedFile)

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceLookupContext.visibleWorkspace.exactFileNamespace(storeRoots: roots)
        let readableService = WorkspaceReadableFileService(store: store)
        let resolution = try await readableService.resolveReadFileRequest(
            WorkspaceExactFileInput.parse("session.py"),
            rootScope: .visibleWorkspace,
            rootRefs: roots,
            namespace: namespace
        )
        guard case let .workspace(match) = resolution else {
            return XCTFail("Expected the root file")
        }
        XCTAssertEqual(match.canonicalPath, "session.py")
        let applyResolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(match.canonicalPath),
            namespace: namespace
        )
        guard case let .matched(applyMatch) = applyResolution else {
            return XCTFail("Expected the read path to resolve for apply_edits")
        }
        XCTAssertEqual(applyMatch.file.id, match.file.id)

        let host = WorkspaceFileEditHost(
            store: store,
            target: .existing(applyMatch.file),
            lookupRootScope: .visibleWorkspace,
            createPathResolutionPolicy: .canonicalAliasFirst,
            selectCreatedFiles: false
        )
        _ = try await ApplyEditsService(engine: .default, host: host).run(
            ApplyEditsRequest(
                path: match.canonicalPath,
                mode: .single(search: "root", replace: "edited", replaceAll: false),
                verbose: true
            )
        )

        XCTAssertEqual(try String(contentsOf: rootFile, encoding: .utf8), "edited token\n")
        XCTAssertEqual(try String(contentsOf: nestedFile, encoding: .utf8), "nested token\n")
    }

    func testIgnoredLiteralCollisionDoesNotFallThroughToAlias() async throws {
        let parent = try makeTemporaryDirectory(name: "IgnoredLiteralCollision")
        let root = parent.appendingPathComponent("mimic", isDirectory: true)
        let rootFile = root.appendingPathComponent("session.py")
        let ignoredLiteral = root.appendingPathComponent("mimic/session.py")
        try write("mimic/session.py\n", to: root.appendingPathComponent(".gitignore"))
        try write("alias target\n", to: rootFile)
        try write("literal target\n", to: ignoredLiteral)

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
        let resolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse("mimic/session.py"),
            namespace: namespace
        )
        guard case let .matched(match) = resolution else {
            return XCTFail("Expected the ignored literal file")
        }
        XCTAssertEqual(match.file.standardizedFullPath, StandardizedPath.absolute(ignoredLiteral.path))
        XCTAssertTrue(match.canonicalPath.hasSuffix("//mimic/session.py"))

        let applyResolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(match.canonicalPath),
            namespace: namespace
        )
        guard case let .matched(applyMatch) = applyResolution else {
            return XCTFail("Expected the ignored read path to resolve for apply_edits")
        }
        XCTAssertEqual(applyMatch.file.id, match.file.id)

        try FileManager.default.removeItem(at: ignoredLiteral)
        let missingResolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(match.canonicalPath),
            namespace: namespace
        )
        XCTAssertEqual(missingResolution, .claimedMissing)
        XCTAssertEqual(try String(contentsOf: rootFile, encoding: .utf8), "alias target\n")
    }

    func testLiteralDirectoryDoesNotFallThroughToAliasFile() async throws {
        let parent = try makeTemporaryDirectory(name: "LiteralDirectoryCollision")
        let root = parent.appendingPathComponent("mimic", isDirectory: true)
        let rootFile = root.appendingPathComponent("session.py")
        let literalDirectory = root.appendingPathComponent("mimic/session.py", isDirectory: true)
        try write("alias target\n", to: rootFile)
        try FileManager.default.createDirectory(at: literalDirectory, withIntermediateDirectories: true)

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
        let readable = try await WorkspaceReadableFileService(store: store).resolveReadFileRequest(
            WorkspaceExactFileInput.parse("mimic/session.py"),
            rootScope: .visibleWorkspace,
            rootRefs: roots,
            namespace: namespace
        )
        guard case .folder = readable else {
            return XCTFail("Expected the literal directory to terminate alias lookup")
        }

        do {
            _ = try await WorkspaceFileMutationService(store: store).resolveExactExistingFileForMutation(
                "mimic/session.py",
                rootScope: .visibleWorkspace
            )
            XCTFail("Expected apply resolution to reject the literal directory")
        } catch {
            XCTAssertEqual(try String(contentsOf: rootFile, encoding: .utf8), "alias target\n")
        }
    }

    func testExplicitCanonicalAliasRoundTripsAcrossDisplayAliasCollisions() async throws {
        let parent = try makeTemporaryDirectory(name: "ExactAliasCollision")
        let rootURLs = ["lookup-a", "lookup-b", "lookup-c"].map {
            parent.appendingPathComponent($0, isDirectory: true)
        }
        for (index, rootURL) in rootURLs.enumerated() {
            try write("root \(index)\n", to: rootURL.appendingPathComponent("shared.txt"))
        }

        let store = WorkspaceFileContextStore()
        for rootURL in rootURLs {
            _ = try await store.loadRoot(path: rootURL.path)
        }
        let lookupRoots = await store.rootRefs(scope: .visibleWorkspace)
            .sorted { $0.standardizedFullPath < $1.standardizedFullPath }
        let clientRoots = [
            WorkspaceRootRef(id: UUID(), name: "Project", fullPath: "/Docs"),
            WorkspaceRootRef(id: UUID(), name: "Project", fullPath: "/tmp/Project"),
            WorkspaceRootRef(id: UUID(), name: "Docs", fullPath: "/else/Docs")
        ]
        let namespace = WorkspaceExactFileNamespace(
            rootBindings: zip(lookupRoots, clientRoots).map { lookupRoot, clientRoot in
                WorkspaceExactFileNamespace.RootBinding(
                    lookupRoot: lookupRoot,
                    lookupRole: .projectedPhysical,
                    clientRoots: [clientRoot],
                    preferredClientRoot: clientRoot
                )
            }
        )
        let firstFile = rootURLs.sorted { $0.path < $1.path }[0].appendingPathComponent("shared.txt")
        let resolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(firstFile.path),
            namespace: namespace
        )
        guard case let .matched(match) = resolution else {
            return XCTFail("Expected the first colliding root file")
        }
        XCTAssertTrue(match.canonicalPath.hasSuffix("//shared.txt"))

        let roundTrip = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(match.canonicalPath),
            namespace: namespace
        )
        guard case let .matched(roundTripMatch) = roundTrip else {
            return XCTFail("Expected the namespace-owned alias to round-trip")
        }
        XCTAssertEqual(roundTripMatch.file.id, match.file.id)
    }

    func testHiddenDuplicateRequiresExplicitCanonicalPath() async throws {
        let parent = try makeTemporaryDirectory(name: "HiddenDuplicate")
        let firstRoot = parent.appendingPathComponent("alpha", isDirectory: true)
        let secondRoot = parent.appendingPathComponent("beta", isDirectory: true)
        let firstFile = firstRoot.appendingPathComponent("shared.txt")
        let secondFile = secondRoot.appendingPathComponent("shared.txt")
        try write("first\n", to: firstFile)
        try write("shared.txt\n", to: secondRoot.appendingPathComponent(".gitignore"))
        try write("second\n", to: secondFile)

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: firstRoot.path)
        _ = try await store.loadRoot(path: secondRoot.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
        let resolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(firstFile.path),
            namespace: namespace
        )
        guard case let .matched(match) = resolution else {
            return XCTFail("Expected the first duplicate")
        }
        XCTAssertTrue(match.canonicalPath.hasSuffix("//shared.txt"))

        let roundTrip = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(match.canonicalPath),
            namespace: namespace
        )
        guard case let .matched(roundTripMatch) = roundTrip else {
            return XCTFail("Expected the explicit canonical path to round-trip")
        }
        XCTAssertEqual(roundTripMatch.file.id, match.file.id)
    }

    func testNestedUnavailableWorktreeDoesNotResolveCanonicalAncestorFile() async throws {
        let parent = try makeTemporaryDirectory(name: "NestedUnavailableWorktree")
        let canonicalRootURL = parent.appendingPathComponent("repo", isDirectory: true)
        let logicalRootURL = canonicalRootURL.appendingPathComponent("project", isDirectory: true)
        let unavailablePhysicalURL = parent.appendingPathComponent("missing-worktree", isDirectory: true)
        let logicalFile = logicalRootURL.appendingPathComponent("Sources/App.swift")
        try write("base token\n", to: logicalFile)

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: canonicalRootURL.path)
        let loadedRoots = await store.rootRefs(scope: .allLoaded)
        let canonicalRoot = try XCTUnwrap(loadedRoots.first)
        let logicalRoot = WorkspaceRootRef(id: UUID(), name: "Project", fullPath: logicalRootURL.path)
        let unavailablePhysical = WorkspaceRootRef(
            id: UUID(),
            name: "Project",
            fullPath: unavailablePhysicalURL.path
        )
        let binding = AgentSessionWorktreeBinding(
            id: "binding-unavailable",
            repositoryID: "repo-unavailable",
            repoKey: "repo-key",
            logicalRootPath: logicalRoot.fullPath,
            logicalRootName: logicalRoot.name,
            worktreeID: "worktree-unavailable",
            worktreeRootPath: unavailablePhysical.fullPath,
            source: "test"
        )
        let projection = WorkspaceRootBindingProjection(
            sessionID: UUID(),
            boundRoots: [
                .init(logicalRoot: logicalRoot, physicalRoot: unavailablePhysical, binding: binding)
            ],
            visibleLogicalRoots: [canonicalRoot, logicalRoot]
        )
        let lookupContext = WorkspaceLookupContext(
            rootScope: projection.lookupRootScope,
            bindingProjection: projection
        )
        let namespace = lookupContext.exactFileNamespace(storeRoots: [canonicalRoot])
        let resolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(logicalFile.path),
            namespace: namespace
        )

        XCTAssertEqual(resolution, .issue(.unresolved(input: logicalFile.path)))
        let readableService = WorkspaceReadableFileService(store: store, homeDirectoryURL: canonicalRootURL)
        let folderResolution = try await readableService.resolveReadFileRequest(
            WorkspaceExactFileInput.parse(logicalRootURL.appendingPathComponent("Sources").path),
            rootScope: lookupContext.rootScope,
            rootRefs: [canonicalRoot],
            namespace: namespace
        )
        guard case let .issue(.unresolved(input)) = folderResolution else {
            return XCTFail("Expected unavailable projected folder to fail closed")
        }
        XCTAssertEqual(input, logicalRootURL.appendingPathComponent("Sources").path)
        let fileResolution = try await readableService.resolveReadFileRequest(
            WorkspaceExactFileInput.parse(logicalFile.path),
            rootScope: lookupContext.rootScope,
            rootRefs: [canonicalRoot],
            namespace: namespace
        )
        guard case let .issue(.unresolved(input)) = fileResolution else {
            return XCTFail("Expected unavailable projected file to avoid external fallback")
        }
        XCTAssertEqual(input, logicalFile.path)
        XCTAssertEqual(try String(contentsOf: logicalFile, encoding: .utf8), "base token\n")
    }

    func testUnavailableWorktreeBlocksRelativeUniquenessBesideAvailableMatch() async throws {
        let parent = try makeTemporaryDirectory(name: "UnavailableWorktreeRelativeCollision")
        let canonicalRootURL = parent.appendingPathComponent("repo", isDirectory: true)
        let unavailablePhysicalURL = parent.appendingPathComponent("missing-worktree", isDirectory: true)
        let canonicalFile = canonicalRootURL.appendingPathComponent("Sources/App.swift")
        try write("base token\n", to: canonicalFile)

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: canonicalRootURL.path)
        let loadedRoots = await store.rootRefs(scope: .allLoaded)
        let canonicalRoot = try XCTUnwrap(loadedRoots.first)
        let logicalRoot = WorkspaceRootRef(id: UUID(), name: "Project", fullPath: "/logical/project")
        let unavailablePhysical = WorkspaceRootRef(
            id: UUID(),
            name: "Project",
            fullPath: unavailablePhysicalURL.path
        )
        let projection = WorkspaceRootBindingProjection(
            sessionID: UUID(),
            boundRoots: [
                .init(
                    logicalRoot: logicalRoot,
                    physicalRoot: unavailablePhysical,
                    binding: AgentSessionWorktreeBinding(
                        id: "binding-unavailable-collision",
                        repositoryID: "repo-unavailable-collision",
                        repoKey: "repo-key",
                        logicalRootPath: logicalRoot.fullPath,
                        logicalRootName: logicalRoot.name,
                        worktreeID: "worktree-unavailable-collision",
                        worktreeRootPath: unavailablePhysical.fullPath,
                        source: "test"
                    )
                )
            ],
            visibleLogicalRoots: [canonicalRoot, logicalRoot]
        )
        let namespace = WorkspaceLookupContext(
            rootScope: projection.lookupRootScope,
            bindingProjection: projection
        ).exactFileNamespace(storeRoots: [canonicalRoot])

        let relativeResolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse("Sources/App.swift"),
            namespace: namespace
        )
        XCTAssertEqual(relativeResolution, .issue(.unresolved(input: "Sources/App.swift")))

        let absoluteResolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(canonicalFile.path),
            namespace: namespace
        )
        guard case let .matched(match) = absoluteResolution else {
            return XCTFail("Expected the absolute canonical file to remain addressable")
        }
        XCTAssertTrue(match.canonicalPath.hasSuffix("//Sources/App.swift"))
    }

    func testNestedBoundLogicalAbsolutePathResolvesWorktree() async throws {
        let parent = try makeTemporaryDirectory(name: "NestedBoundLogicalRoot")
        let canonicalRootURL = parent.appendingPathComponent("repo", isDirectory: true)
        let logicalRootURL = canonicalRootURL.appendingPathComponent("project", isDirectory: true)
        let physicalRootURL = parent.appendingPathComponent("worktree", isDirectory: true)
        let logicalFile = logicalRootURL.appendingPathComponent("Sources/App.swift")
        let physicalFile = physicalRootURL.appendingPathComponent("Sources/App.swift")
        try write("base token\n", to: logicalFile)
        try write("worktree token\n", to: physicalFile)

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: canonicalRootURL.path)
        _ = try await store.loadRoot(path: physicalRootURL.path)
        let loadedRoots = await store.rootRefs(scope: .allLoaded)
        let canonicalRoot = try XCTUnwrap(loadedRoots.first {
            $0.standardizedFullPath == StandardizedPath.absolute(canonicalRootURL.path)
        })
        let physicalRoot = try XCTUnwrap(loadedRoots.first {
            $0.standardizedFullPath == StandardizedPath.absolute(physicalRootURL.path)
        })
        let logicalRoot = WorkspaceRootRef(id: UUID(), name: "Project", fullPath: logicalRootURL.path)
        let binding = AgentSessionWorktreeBinding(
            id: "binding-nested",
            repositoryID: "repo-nested",
            repoKey: "repo-key",
            logicalRootPath: logicalRoot.fullPath,
            logicalRootName: logicalRoot.name,
            worktreeID: "worktree-nested",
            worktreeRootPath: physicalRoot.fullPath,
            source: "test"
        )
        let projection = WorkspaceRootBindingProjection(
            sessionID: UUID(),
            boundRoots: [.init(logicalRoot: logicalRoot, physicalRoot: physicalRoot, binding: binding)],
            visibleLogicalRoots: [canonicalRoot, logicalRoot]
        )
        let lookupContext = WorkspaceLookupContext(
            rootScope: projection.lookupRootScope,
            bindingProjection: projection
        )
        let namespace = lookupContext.exactFileNamespace(storeRoots: loadedRoots)
        let folderResolution = try await WorkspaceReadableFileService(store: store).resolveReadFileRequest(
            WorkspaceExactFileInput.parse(logicalRootURL.appendingPathComponent("Sources").path),
            rootScope: lookupContext.rootScope,
            rootRefs: loadedRoots,
            namespace: namespace
        )
        guard case .folder = folderResolution else {
            return XCTFail("Expected the logical folder to resolve through the physical worktree")
        }
        let resolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(logicalFile.path),
            namespace: namespace
        )
        guard case let .matched(match) = resolution else {
            return XCTFail("Expected the nested logical path to resolve into the worktree")
        }
        XCTAssertEqual(match.file.standardizedFullPath, StandardizedPath.absolute(physicalFile.path))

        let roundTrip = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(match.canonicalPath),
            namespace: namespace
        )
        guard case let .matched(roundTripMatch) = roundTrip else {
            return XCTFail("Expected the worktree read path to resolve for apply_edits")
        }
        XCTAssertEqual(roundTripMatch.file.id, match.file.id)
        let host = WorkspaceFileEditHost(store: store, target: .existing(roundTripMatch.file))
        _ = try await ApplyEditsService(engine: .default, host: host).run(
            ApplyEditsRequest(
                path: match.canonicalPath,
                mode: .single(search: "worktree", replace: "edited", replaceAll: false),
                verbose: true
            )
        )
        XCTAssertEqual(try String(contentsOf: logicalFile, encoding: .utf8), "base token\n")
        XCTAssertEqual(try String(contentsOf: physicalFile, encoding: .utf8), "edited token\n")
    }

    func testCanonicalPathRoundTripsLeadingWhitespaceRelativePath() async throws {
        let root = try makeTemporaryDirectory(name: "LeadingWhitespaceRelativePath")
        let fileURL = root.appendingPathComponent(" Target.swift")
        try write("whitespace token\n", to: fileURL)
        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
        let resolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(fileURL.path),
            namespace: namespace
        )
        guard case let .matched(match) = resolution else {
            return XCTFail("Expected the whitespace-leading workspace file, got \(resolution)")
        }
        XCTAssertEqual(match.canonicalPath, " Target.swift")

        let roundTrip = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse(match.canonicalPath),
            namespace: namespace
        )
        guard case let .matched(roundTripMatch) = roundTrip else {
            return XCTFail("Expected the whitespace-leading canonical path to round-trip")
        }
        XCTAssertEqual(roundTripMatch.file.id, match.file.id)
    }

    func testAbsoluteWorkspaceRootResolvesAsFolder() async throws {
        let root = try makeTemporaryDirectory(name: "AbsoluteWorkspaceRootFolder")
        try write("content\n", to: root.appendingPathComponent("Target.swift"))
        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
        let resolution = try await WorkspaceReadableFileService(store: store).resolveReadFileRequest(
            WorkspaceExactFileInput.parse(root.path),
            rootScope: .visibleWorkspace,
            rootRefs: roots,
            namespace: namespace
        )
        guard case .folder = resolution else {
            return XCTFail("Expected the loaded root path to resolve as a folder, got \(resolution)")
        }
    }

    func testMalformedMutationInputsUseFileManagerErrorBoundary() async throws {
        let store = WorkspaceFileContextStore()
        let mutationService = WorkspaceFileMutationService(store: store)
        for input in ["", " \n ", "../Target.swift", "root///Target.swift", "bad\0path"] {
            do {
                _ = try await mutationService.resolveExactExistingFileForMutation(input)
                XCTFail("Expected malformed input to fail: \(input)")
            } catch is FileManagerError {
                continue
            } catch {
                XCTFail("Expected FileManagerError for \(input), got \(error)")
            }
        }
    }

    func testApprovedWriteRejectsReplacementAfterPreview() async throws {
        let root = try makeTemporaryDirectory(name: "ApprovedWriteReplacement")
        let fileURL = root.appendingPathComponent("Target.swift")
        try write("reviewed token\n", to: fileURL)
        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
        let resolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse("Target.swift"),
            namespace: namespace
        )
        guard case let .matched(match) = resolution else {
            return XCTFail("Expected the target file")
        }
        let host = WorkspaceFileEditHost(store: store, target: .existing(match.file))
        let preview = try await ApplyEditsService(engine: .default, host: host).preview(
            ApplyEditsRequest(
                path: match.canonicalPath,
                mode: .single(search: "reviewed", replace: "approved", replaceAll: false),
                verbose: true
            )
        )
        let originalText = try XCTUnwrap(preview.originalText)
        try write("replacement content\n", to: fileURL)

        do {
            try await host.writeTextIfUnchanged(
                path: match.canonicalPath,
                content: preview.result.updatedText,
                expectedOriginalText: originalText
            )
            XCTFail("Expected the approved write to reject replacement content")
        } catch FileSystemError.fileContentChanged {
            XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "replacement content\n")
        } catch {
            XCTFail("Expected fileContentChanged, got \(error)")
        }

        try await host.writeTextIfUnchanged(
            path: match.canonicalPath,
            content: "accepted replacement\n",
            expectedOriginalText: "replacement content\n"
        )
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "accepted replacement\n")
    }

    func testApprovedWriteUsesStreamedPreviewEncodingAtCommit() async throws {
        let root = try makeTemporaryDirectory(name: "ApprovedWriteStreamedEncoding")
        let fileURL = root.appendingPathComponent("Large.swift")
        let fileBody = String(repeating: "a", count: 1_100_000) + " reviewed token\n"
        let reviewedText = "\u{FEFF}" + fileBody
        var originalData = Data([0xFF, 0xFE])
        try originalData.append(XCTUnwrap(fileBody.data(using: .utf16LittleEndian)))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try originalData.write(to: fileURL)

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
        let resolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse("Large.swift"),
            namespace: namespace
        )
        guard case let .matched(match) = resolution else {
            return XCTFail("Expected the streamed target file")
        }
        let host = WorkspaceFileEditHost(store: store, target: .existing(match.file))
        let preview = try await ApplyEditsService(engine: .default, host: host).preview(
            ApplyEditsRequest(
                path: match.canonicalPath,
                mode: .single(search: "reviewed", replace: "approved", replaceAll: false),
                verbose: false
            )
        )
        let previewOriginalText = try XCTUnwrap(preview.originalText)
        XCTAssertEqual(previewOriginalText, reviewedText)

        try await host.writeTextIfUnchanged(
            path: match.canonicalPath,
            content: preview.result.updatedText,
            expectedOriginalText: previewOriginalText
        )
        XCTAssertEqual(
            try String(contentsOf: fileURL, encoding: .utf16LittleEndian),
            "\u{FEFF}" + String(repeating: "a", count: 1_100_000) + " approved token\n"
        )
    }

    func testMissingResolvedTargetFailsInsteadOfReadingEmptyContent() async throws {
        let root = try makeTemporaryDirectory(name: "MissingResolvedTarget")
        let fileURL = root.appendingPathComponent("Target.swift")
        try write("content\n", to: fileURL)
        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let namespace = WorkspaceExactFileNamespace.identity(roots: roots)
        let resolution = try await store.resolveExactExistingWorkspaceFile(
            WorkspaceExactFileInput.parse("Target.swift"),
            namespace: namespace
        )
        guard case let .matched(match) = resolution else {
            return XCTFail("Expected the target file")
        }
        let host = WorkspaceFileEditHost(store: store, target: .existing(match.file))
        try FileManager.default.removeItem(at: fileURL)

        do {
            _ = try await host.readText(path: match.canonicalPath)
            XCTFail("Expected a missing resolved target to fail")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    private func makeTemporaryDirectory(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepoPromptTests", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

#if DEBUG
    private actor ExactResolutionPeerProbe {
        private(set) var count = 0

        func record() {
            count += 1
        }
    }

    private enum MCPPathContractAsyncWait {
        struct Timeout: Error, LocalizedError {
            let description: String
            let seconds: TimeInterval

            var errorDescription: String? {
                "Timed out after \(seconds)s waiting for \(description)"
            }
        }

        static func waitUntil(
            _ description: String,
            timeout: TimeInterval,
            condition: @escaping () async -> Bool
        ) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(max(0, timeout)))

            while await !condition() {
                try Task.checkCancellation()
                guard clock.now < deadline else {
                    throw Timeout(description: description, seconds: timeout)
                }
                await Task.yield()
            }
        }
    }

    private final class MCPPathContractReleaseGate: @unchecked Sendable {
        private let name: String
        private let lock = NSLock()
        private var entered = false
        private var released = false
        private var releaseWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
        private var cancelledReleaseWaiters = Set<UUID>()
        private var timedOutReleaseWaiters = Set<UUID>()
        private var entryWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
        private var cancelledEntryWaiters = Set<UUID>()
        private var timedOutEntryWaiters = Set<UUID>()

        init(name: String) {
            self.name = name
        }

        func enterAndWait() async {
            let waiterID = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    registerReleaseWaiter(continuation, id: waiterID, ignoresCancellation: false)
                }
            } onCancel: {
                cancelReleaseWaiter(id: waiterID)
            }
        }

        func enterAndWaitIgnoringCancellationUntilRelease(timeout: TimeInterval = 30) async {
            let waiterID = UUID()
            let timeoutTask = Task.detached { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, timeout)))
                guard !Task.isCancelled else { return }
                self?.timeoutReleaseWaiter(id: waiterID, seconds: timeout)
            }
            await withCheckedContinuation { continuation in
                registerReleaseWaiter(continuation, id: waiterID, ignoresCancellation: true)
            }
            timeoutTask.cancel()
            await timeoutTask.value
        }

        @discardableResult
        func waitUntilEntered(timeout: TimeInterval = 10) async -> Bool {
            let waiterID = UUID()
            let timeoutTask = Task.detached { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, timeout)))
                guard !Task.isCancelled else { return }
                self?.timeoutEntryWaiter(id: waiterID, seconds: timeout)
            }
            let didEnter = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    registerEntryWaiter(continuation, id: waiterID)
                }
            } onCancel: {
                cancelEntryWaiter(id: waiterID)
            }
            timeoutTask.cancel()
            await timeoutTask.value
            return didEnter
        }

        func release() {
            lock.lock()
            released = true
            let pending = Array(releaseWaiters.values)
            releaseWaiters.removeAll()
            cancelledReleaseWaiters.removeAll()
            timedOutReleaseWaiters.removeAll()
            lock.unlock()
            pending.forEach { $0.resume() }
        }

        private func registerReleaseWaiter(
            _ continuation: CheckedContinuation<Void, Never>,
            id: UUID,
            ignoresCancellation: Bool
        ) {
            lock.lock()
            entered = true
            let enteredWaiters = Array(entryWaiters.values)
            entryWaiters.removeAll()
            cancelledEntryWaiters.removeAll()
            timedOutEntryWaiters.removeAll()
            let shouldResume = released
                || timedOutReleaseWaiters.remove(id) != nil
                || (!ignoresCancellation && (Task.isCancelled || cancelledReleaseWaiters.remove(id) != nil))
            if !shouldResume {
                releaseWaiters[id] = continuation
            }
            lock.unlock()

            enteredWaiters.forEach { $0.resume(returning: true) }
            if shouldResume {
                continuation.resume()
            }
        }

        private func registerEntryWaiter(_ continuation: CheckedContinuation<Bool, Never>, id: UUID) {
            lock.lock()
            let didEnter: Bool?
            if entered {
                didEnter = true
            } else if Task.isCancelled
                || cancelledEntryWaiters.remove(id) != nil
                || timedOutEntryWaiters.remove(id) != nil
            {
                didEnter = false
            } else {
                entryWaiters[id] = continuation
                didEnter = nil
            }
            lock.unlock()

            if let didEnter {
                continuation.resume(returning: didEnter)
            }
        }

        private func cancelReleaseWaiter(id: UUID) {
            lock.lock()
            let continuation = releaseWaiters.removeValue(forKey: id)
            if continuation == nil, !released {
                cancelledReleaseWaiters.insert(id)
            }
            lock.unlock()
            continuation?.resume()
        }

        private func timeoutReleaseWaiter(id: UUID, seconds: TimeInterval) {
            lock.lock()
            let continuation = releaseWaiters.removeValue(forKey: id)
            let shouldFail = continuation != nil || !released
            if continuation == nil, !released {
                timedOutReleaseWaiters.insert(id)
            }
            lock.unlock()

            guard shouldFail else { return }
            XCTFail("Timed out waiting for \(name) release after \(seconds)s")
            continuation?.resume()
        }

        private func cancelEntryWaiter(id: UUID) {
            lock.lock()
            let continuation = entryWaiters.removeValue(forKey: id)
            if continuation == nil, !entered {
                cancelledEntryWaiters.insert(id)
            }
            lock.unlock()
            continuation?.resume(returning: false)
        }

        private func timeoutEntryWaiter(id: UUID, seconds: TimeInterval) {
            lock.lock()
            let continuation = entryWaiters.removeValue(forKey: id)
            let shouldFail = continuation != nil || !entered
            if continuation == nil, !entered {
                timedOutEntryWaiters.insert(id)
            }
            lock.unlock()

            guard shouldFail else { return }
            XCTFail("Timed out waiting for \(name) to enter after \(seconds)s")
            continuation?.resume(returning: false)
        }
    }
#endif
