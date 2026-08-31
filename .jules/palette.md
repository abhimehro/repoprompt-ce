## 2024-05-14 - Add Accessibility Labels to Icon-Only Buttons
**Learning:** In SwiftUI, `hoverTooltip` does not automatically provide an accessibility label. Icon-only buttons with `hoverTooltip` need an explicit `.accessibilityLabel` to be read correctly by VoiceOver and meet WCAG requirements.
**Action:** When adding or reviewing icon-only buttons, always ensure an `.accessibilityLabel` is applied in addition to any visual tooltip modifiers like `.hoverTooltip`.
