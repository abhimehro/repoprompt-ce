## 2025-10-01 - Missing Accessibility Labels on Icon-Only Copy Buttons
**Learning:** Icon-only buttons used for copying code (e.g., in CodeBlockView) have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`). Screen readers may read out meaningless icon names or nothing.
**Action:** Added `.accessibilityLabel("Copy code to clipboard")` to copy buttons in `CodeBlockView.swift`. Next time, ensure all icon-only interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.
## 2025-10-16 - Missing Accessibility Labels on Workflows Configure & Session Row Action Buttons
**Learning:** Several icon-only action buttons (like move, delete, rename, pin, etc.) had a `.hoverTooltip` for visual users but lacked `.accessibilityLabel` for VoiceOver/screen-readers, which leads to meaningless reading of the elements.
**Action:** Added explicit `.accessibilityLabel` alongside `.hoverTooltip` for those interactive button elements in `AgentWorkflowsConfigureSheet.swift` and `AgentSessionRows.swift`. Ensure we systematically audit icon-only buttons for this pairing.
