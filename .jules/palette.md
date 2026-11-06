## 2025-10-01 - Missing Accessibility Labels on Icon-Only Copy Buttons
**Learning:** Icon-only buttons used for copying code (e.g., in CodeBlockView) have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`). Screen readers may read out meaningless icon names or nothing.
**Action:** Added `.accessibilityLabel("Copy code to clipboard")` to copy buttons in `CodeBlockView.swift`. Next time, ensure all icon-only interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.
## 2024-11-02 - Missing Accessibility Labels on Workflows Buttons
**Learning:** Many icon-only buttons have hover tooltips but miss `.accessibilityLabel`, leading to a poor experience for screen reader users.
**Action:** Added `.accessibilityLabel` to match `.hoverTooltip` across workflow and context components. Always ensure `accessibilityLabel` accompanies `hoverTooltip` on interactive elements.
