## 2025-07-07 - Screen Reader Support for Toolbar Notifications
**Learning:** Found custom SwiftUI `.hoverTooltip(_)` modifier doesn't automatically create accessibility labels for screen readers. The main toolbar notification button and its inner popup items (mute, unmute, dismiss) lacked `accessibilityLabel` bindings, rendering them unlabeled for VoiceOver users.
**Action:** Always apply explicit `.accessibilityLabel(_)` alongside `.hoverTooltip(_)` for icon-only and interactive elements to satisfy WCAG 'Label in Name' criteria in SwiftUI.
