## 2026-06-24 - Tooltips and Accessibility Labels
**Learning:** The custom `.hoverTooltip()` modifier does not automatically provide an accessibility label for screen readers. Both `.hoverTooltip()` and `.accessibilityLabel()` must be applied to icon-only buttons to ensure they are fully accessible.
**Action:** When adding `.hoverTooltip()` to icon-only buttons, always ensure an `.accessibilityLabel()` with the same or similar descriptive text is also added.
