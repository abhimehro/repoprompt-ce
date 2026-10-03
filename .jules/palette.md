## 2025-07-07 - Notifications Button Accessibility
**Learning:** Icon-only buttons with dynamic badges need descriptive tooltips/labels that include the badge count for accessibility. Empty states need conditional handling.
**Action:** Use `.hoverTooltip` (or `.help`) on icon-only notification buttons and conditionally include the count, e.g., `isEmpty ? "Notifications" : "Notifications, \(count) unread"`.
