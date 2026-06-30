## 2024-07-01 - Missing Accessibility Labels on Tooltips
**Learning:** Found multiple instances where `.hoverTooltip()` was used without a corresponding `.accessibilityLabel()`. Tooltips provide visual guidance but don't automatically announce to screen readers.
**Action:** When adding `.hoverTooltip()`, always pair it with an `.accessibilityLabel()` containing the same descriptive text to ensure keyboard/VoiceOver users have the same context.
