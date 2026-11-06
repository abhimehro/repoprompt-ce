## 2025-10-01 - Missing Accessibility Labels on Icon-Only Copy Buttons
**Learning:** Icon-only buttons used for copying code (e.g., in CodeBlockView) have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`). Screen readers may read out meaningless icon names or nothing.
**Action:** Added `.accessibilityLabel("Copy code to clipboard")` to copy buttons in `CodeBlockView.swift`. Next time, ensure all icon-only interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.
## 2025-10-02 - Missing Accessibility Labels on Icon-Only Context Drawer Buttons
**Learning:** Many icon-only buttons used in the AgentContextDrawer views have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`).
**Action:** Added `.accessibilityLabel` to buttons in `AgentContextControlDrawerView`, `AgentContextDrawerFilesTab`, `AgentContextDrawerPromptTab`, `AgentContextDrawerTokenEstimatePill`, `AgentContextFileBrowseView`, and `AgentContextSelectedFilesContent` that had a hover tooltip without an accessibility label.
