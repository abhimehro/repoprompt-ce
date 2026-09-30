import Foundation
import RepoPromptDomainRuntime

/// Immutable registration-time caller evidence. A delayed tool body may not borrow a later turn's
/// run attempt or a rebound tab even if its connection still resolves to the same session UUID.
struct AgentSelfMCPCallOrigin: Equatable {
    let endpoint: DomainAgentSessionLinkEndpointIdentity
    let runID: UUID
    let runAttemptID: UUID

    @TaskLocal static var current: Self?
}
