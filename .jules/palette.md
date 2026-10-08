## 2025-10-01 - Missing Accessibility Labels on Icon-Only Copy Buttons
**Learning:** Icon-only buttons used for copying code (e.g., in CodeBlockView) have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`). Screen readers may read out meaningless icon names or nothing.
**Action:** Added `.accessibilityLabel("Copy code to clipboard")` to copy buttons in `CodeBlockView.swift`. Next time, ensure all icon-only interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.
## 2025-10-08 - Missing Accessibility Labels on Icon-Only Buttons in Custom Modifiers
**Learning:** Icon-only buttons with `.hoverTooltip(_)` don't automatically provide an accessibility label. This is a common pattern for icon buttons where hover tooltips provide visual cues but leave screen readers with just system image names.
**Action:** When adding `.hoverTooltip` to icon buttons, consistently pair it with `.accessibilityLabel` to ensure full screen reader accessibility.
