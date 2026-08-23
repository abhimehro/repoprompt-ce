## 2025-10-27 - Custom Tooltips in SwiftUI hide Accessibility Labels
**Learning:** In SwiftUI, custom modifiers like .hoverTooltip() on icon-only buttons do not automatically expose their text as accessibility labels to VoiceOver. Visually, the user gets a tooltip, but functionally, screen reader users hear nothing.
**Action:** Always explicitly attach .accessibilityLabel() alongside .hoverTooltip() for any interactive element that lacks text content (icon-only buttons).
