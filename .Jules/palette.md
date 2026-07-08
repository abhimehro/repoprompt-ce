## 2024-07-08 - Icon-only Button Accessibility
**Learning:** Icon-only buttons using `hoverTooltip` in `AgentSessionRows.swift` do not automatically inherit an accessibility label; a separate `.accessibilityLabel` must be manually applied next to the tooltip to ensure screen readers can read it.
**Action:** Always pair `.hoverTooltip(...)` with `.accessibilityLabel(...)` when designing icon-only interactable components.
