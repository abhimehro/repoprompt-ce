## 2025-10-01 - Missing Accessibility Labels on Icon-Only Copy Buttons
**Learning:** Icon-only buttons used for copying code (e.g., in CodeBlockView) have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`). Screen readers may read out meaningless icon names or nothing.
**Action:** Added `.accessibilityLabel("Copy code to clipboard")` to copy buttons in `CodeBlockView.swift`. Next time, ensure all icon-only interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.
## 2025-05-19 - Missing Accessibility Labels on Icon-Only Buttons
**Learning:** In SwiftUI, using the custom `.hoverTooltip()` modifier on an icon-only button without explicitly adding `.accessibilityLabel()` causes screen readers to announce either unhelpful default icon text or nothing. This was found globally on multiple components using `hoverTooltip`.
**Action:** When adding `.hoverTooltip()` to icon-only buttons, always accompany it with an `.accessibilityLabel()` using identical or expanded text to ensure full screen reader support.
