## 2024-05-15 - SwiftUI Custom Tooltip Accessibility
**Learning:** Custom modifiers like `.hoverTooltip(_)` do not automatically create accessibility labels for screen readers in this design system.
**Action:** When adding `.hoverTooltip(_)` to icon-only buttons, explicitly apply `.accessibilityLabel(_)` with the same label text to ensure VoiceOver users can access the button name.
