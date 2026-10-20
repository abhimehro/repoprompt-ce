## 2025-10-01 - Missing Accessibility Labels on Icon-Only Copy Buttons
**Learning:** Icon-only buttons used for copying code (e.g., in CodeBlockView) have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`). Screen readers may read out meaningless icon names or nothing.
**Action:** Added `.accessibilityLabel("Copy code to clipboard")` to copy buttons in `CodeBlockView.swift`. Next time, ensure all icon-only interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.

## 2026-10-12 - Missing Accessibility Labels on Icon-Only Workflow Settings Buttons
**Learning:** Icon-only buttons used for configuring workflows in `AgentWorkflowsConfigureSheet` had hover tooltips but lacked explicit screen reader accessibility labels (`.accessibilityLabel`). A complex, conditionally formatted tooltip can also be duplicated as a similarly conditional `.accessibilityLabel`.
**Action:** Added `.accessibilityLabel` to all icon-only interactive elements in `AgentWorkflowsConfigureSheet.swift` mirroring their respective `.hoverTooltip` strings, including conditional string logic. Next time, always mirror conditional `.hoverTooltip` text into a `.accessibilityLabel` for complex dynamic buttons.
