## 2025-10-01 - Missing Accessibility Labels on Icon-Only Copy Buttons
**Learning:** Icon-only buttons used for copying code (e.g., in CodeBlockView) have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`). Screen readers may read out meaningless icon names or nothing.
**Action:** Added `.accessibilityLabel("Copy code to clipboard")` to copy buttons in `CodeBlockView.swift`. Next time, ensure all icon-only interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.
## 2026-11-03 - Pattern: Missing Accessibility Labels on Tooltips
**Learning:** Found widespread missing accessibility labels on SwiftUI icon-only buttons using `.hoverTooltip(_)`. Without `.accessibilityLabel(_)`, screen readers do not read out the intent of these controls.
**Action:** Applied `.accessibilityLabel(_)` to correspond with all instances of `.hoverTooltip(_)` across the `AgentMode` views. Next time, always enforce checking for `.accessibilityLabel` whenever adding or modifying `.hoverTooltip`.
