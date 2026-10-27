import Foundation

@MainActor
extension AgentModeViewModel {
    func makeTranscriptUISnapshot() -> AgentTranscriptUISnapshot {
        let tabID = currentTabID
        let session = activeSession
        return AgentTranscriptUISnapshot(
            currentTabID: tabID,
            presentation: scopedActiveTranscriptPresentation(for: tabID),
            isHydrated: isActiveTranscriptPresentationHydrated(for: tabID),
            presentationRevision: activeTranscriptPresentationRevision(for: tabID),
            followBindingState: activeTranscriptFollowBindingState,
            activeSessionLoadInProgressTabID: activeSessionLoadInProgressTabID,
            activeBashLiveExecutionByItemID: activeBashLiveExecutionByItemID,
            runtimeFooterByItemID: agentMessageRuntimeFooters(for: tabID),
            fallbackFollowArmingState: session?.transcriptAutoFollowArmingState ?? .armed,
            archivedBlocks: session?.archivedTranscriptSnapshot.blocks ?? []
        )
    }

    func syncTranscriptUIState() {
        ui.transcript.update(makeTranscriptUISnapshot())
    }
}
