## 2025-07-07 - Add accessibility labels to custom buttons with tooltips
**Learning:** In SwiftUI, `hoverTooltip` does not automatically provide an accessibility label for VoiceOver users. For icon-only buttons (like those in notifications), we need to explicitly set `accessibilityLabel(_)` in addition to the tooltip.
**Action:** Always add `.accessibilityLabel` to icon-only interactive elements alongside `.hoverTooltip`.
