## 2024-03-24 - Accessibility labels for custom hoverTooltip
**Learning:** The codebase has a custom modifier `.hoverTooltip` used on buttons. However, it does not automatically add an accessibility label, requiring explicit `.accessibilityLabel` along with it on icon-only buttons for screen readers to announce them correctly. This is documented in memory as well.
**Action:** When adding or modifying icon-only buttons with `.hoverTooltip`, ensure they also have an `.accessibilityLabel`.
