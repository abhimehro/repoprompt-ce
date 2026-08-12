import Foundation

@MainActor
final class CodexContextUsageEstimator: ContextUsageEstimating {
    let agent: AgentProviderKind = .codexExec

    @discardableResult
    func enqueueUserTurnEstimate(
        messageForProvider _: String,
        session _: AgentModeViewModel.TabSession
    ) -> Int {
        0
    }

    @discardableResult
    func replaceNextQueuedUserTurnEstimate(
        messageForProvider _: String,
        session _: AgentModeViewModel.TabSession
    ) -> Int? {
        nil
    }

    func dequeueQueuedUserTurnEstimate(session _: AgentModeViewModel.TabSession) -> Int? {
        nil
    }

    func beginTurn(session _: AgentModeViewModel.TabSession, initialMessage _: String) {
        // Codex uses native token usage events.
    }

    func addUserInputTokens(_ tokens: Int, session _: AgentModeViewModel.TabSession) {
        _ = tokens
    }

    func addToolInputPayload(_ payload: String?, session _: AgentModeViewModel.TabSession) {
        _ = payload
    }

    func addToolOutputPayload(_ payload: String?, session _: AgentModeViewModel.TabSession) {
        _ = payload
    }

    @discardableResult
    func ingestUsageSignal(
        promptTokens _: Int?,
        completionTokens _: Int?,
        contextUsedTokens _: Int?,
        modelContextWindow _: Int?,
        session _: AgentModeViewModel.TabSession
    ) -> ContextUsageSnapshot? {
        nil
    }

    @discardableResult
    func ingestTurnFinalizationSignal(
        contextUsedTokens _: Int?,
        modelContextWindow _: Int?,
        session _: AgentModeViewModel.TabSession
    ) -> ContextUsageSnapshot? {
        nil
    }

    func ingestStatusSignal(_ statusText: String?, session _: AgentModeViewModel.TabSession) {
        _ = statusText
    }

    func ingestSystemSignal(_ systemText: String?, session _: AgentModeViewModel.TabSession) {
        _ = systemText
    }

    @discardableResult
    func finalizeTurn(
        promptTokens _: Int?,
        completionTokens _: Int?,
        contextUsedTokens _: Int?,
        session _: AgentModeViewModel.TabSession
    ) -> Bool {
        false
    }

    @discardableResult
    func ingestNativeContextUsage(
        _ usage: AgentContextUsage?,
        session: AgentModeViewModel.TabSession
    ) -> ContextUsageSnapshot? {
        let next = ContextUsageSnapshot.fromAgentContextUsage(
            usage,
            source: .codexNativeUsage,
            confidence: .exact
        )
        if session.contextUsageSnapshot != next {
            session.contextUsageSnapshot = next
            return next
        }
        return nil
    }
}
