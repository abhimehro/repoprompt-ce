## 2026-06-21 - Custom Tooltip Requires Manual Accessibility Label
**Learning:** The project's custom `.hoverTooltip()` modifier does not automatically generate an `.accessibilityLabel()` for screen readers. When applied to icon-only buttons, it only provides visual hover text.
**Action:** Always ensure that icon-only buttons using `.hoverTooltip()` also explicitly receive an `.accessibilityLabel()` with the corresponding descriptive text.
