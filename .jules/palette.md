## 2025-10-01 - Missing Accessibility Labels on Icon-Only Copy Buttons
**Learning:** Icon-only buttons used for copying code (e.g., in CodeBlockView) have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`). Screen readers may read out meaningless icon names or nothing.
**Action:** Added `.accessibilityLabel("Copy code to clipboard")` to copy buttons in `CodeBlockView.swift`. Next time, ensure all icon-only interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.
## 2025-10-02 - Missing Accessibility Labels on Dual Action Buttons
**Learning:** Dual action buttons (`CompactDualActionButton`, `DualClickPopoverButton`) have hover tooltips but lacked explicit screen reader accessibility labels. Screen readers may read out meaningless names or nothing.
**Action:** Added `.accessibilityLabel` to tooltips in `CompactDualActionButton.swift` and `DualClickPopoverButton.swift`. Next time, ensure all interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.
