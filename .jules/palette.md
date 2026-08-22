## 2024-11-20 - Swift UI Button Accessibility
**Learning:** In SwiftUI, `Button(action:)` items lacking text content (such as icon-only buttons) do not implicitly read well for VoiceOver users without explicit `.accessibilityLabel` modifiers, especially when using generic Tooltip modifiers.
**Action:** When auditing or implementing icon-only buttons in SwiftUI, always pair `.hoverTooltip(...)` with `.accessibilityLabel(...)` to ensure correct screen reader behavior without breaking the WCAG "Label in Name" rule.
