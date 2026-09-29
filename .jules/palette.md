## 2025-03-09 - Ensure Icon-Only Buttons Have Both Tooltips and Accessibility Labels
**Learning:** Some icon-only buttons had tooltips but no accessibility labels, or accessibility labels but no tooltips. Both are required for a complete UX: tooltips for sighted mouse users to discover functionality, and accessibility labels for screen reader users.
**Action:** Always verify that icon-only buttons include both `.hoverTooltip(...)` and `.accessibilityLabel(...)` modifiers.
