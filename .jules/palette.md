## 2024-11-12 - Explicit .accessibilityLabel() alongside custom .hoverTooltip() for Icon-only Buttons
**Learning:** In this SwiftUI codebase, the custom `.hoverTooltip(_)` modifier on icon-only buttons does not automatically provide an accessibility label. Icon-only buttons with just `.hoverTooltip()` are missing context for VoiceOver and screen readers.
**Action:** Explicitly include `.accessibilityLabel(_)` alongside `.hoverTooltip(_)` on icon-only buttons to ensure full screen reader accessibility.
