## 2024-05-24 - Initializing palette journal
## 2024-05-24 - Hover Tooltips and Accessibility Labels
**Learning:** Found several icon-only buttons (like NotificationsButtonView and SettingsButton) that had `hoverTooltip` or raw icons but lacked `accessibilityLabel`. In SwiftUI, `hoverTooltip` is a custom modifier that doesn't inherently add an accessibility label for VoiceOver, so they must be added explicitly alongside the tooltip for icon-only interactive elements.
**Action:** When inspecting buttons with custom tooltips or just icons, ensure `.accessibilityLabel` is explicitly added so VoiceOver users get the same context as sighted users.
