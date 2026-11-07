## 2024-05-28 - Missing Accessibility Labels on Icon-only Buttons
**Learning:** Found multiple places where icon-only buttons (like notifications, copying code, and workspace approval) were missing `.accessibilityLabel`. In SwiftUI, `Button(action:) { Image(systemName:) }` lacks inherent text for VoiceOver unless an accessibility label is provided. Even with tooltips (`.hoverTooltip`), VoiceOver may not announce the action correctly.
**Action:** Always verify icon-only buttons have an explicit `.accessibilityLabel` applied to them so screen reader users understand their purpose.
