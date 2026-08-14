import re

file_paths = [
    "Sources/RepoPrompt/Infrastructure/MCP/AppSettingsMCPService.swift",
    "Sources/RepoPrompt/Infrastructure/MCP/ToolOutputFormatter.swift",
    "Sources/RepoPrompt/Infrastructure/MCP/Agent/AgentMCPToolHelpers.swift",
    "Sources/RepoPrompt/Infrastructure/MCP/Agent/AgentRunMCPToolService.swift",
    "Sources/RepoPrompt/Infrastructure/WorkspaceContext/Slices/PartitionStore.swift",
    "Sources/RepoPrompt/Infrastructure/AI/ACP/ACPAgentSessionController.swift",
    "Sources/RepoPrompt/Infrastructure/AI/Providers/ClaudeCode/SDK/ClaudeSDKNDJSONTranslator.swift",
    "Sources/RepoPrompt/Infrastructure/AI/Providers/ClaudeCode/SDK/ClaudeNativeProcessSessionController.swift",
    "Sources/RepoPrompt/Infrastructure/AI/Providers/Codex/AppServer/CodexNativeSessionController.swift",
    "Sources/RepoPrompt/Infrastructure/Process/CLIProcessLogCollector.swift",
    "Sources/RepoPrompt/Infrastructure/Persistence/Presets/PresetFileStore.swift",
    "Sources/RepoPrompt/Infrastructure/VCS/GitDiff/GitDiffSnapshotStore.swift",
    "Sources/RepoPrompt/Infrastructure/VCS/GitService.swift",
    "Sources/RepoPrompt/App/Changelog.swift",
    "Sources/RepoPrompt/Features/Settings/Models/GlobalSettingsFileStore.swift",
    "Sources/RepoPrompt/Features/Chat/ViewModels/Oracle/OracleViewModel+MCP.swift",
    "Sources/RepoPrompt/Features/AgentMode/History/HistoryMCPToolService.swift",
    "Sources/RepoPrompt/Features/Diagnostics/AgentMode/Stress/AgentChatStressHarness.swift",
]

for file_path in file_paths:
    with open(file_path, "r") as f:
        content = f.read()

    # Try to find inline instantiations that can be optimized.
    # Note: I'll leave these for a future run, but for now the goal is to NOT fail the CI.
    # I already documented the Worktree flake, but CI failed again.
    pass
