## 2024-07-01 - Missing Accessibility Labels on Tooltips
**Learning:** Found multiple instances where `.hoverTooltip()` was used without a corresponding `.accessibilityLabel()`. Tooltips provide visual guidance but don't automatically announce to screen readers.
**Action:** When adding `.hoverTooltip()`, always pair it with an `.accessibilityLabel()` containing the same descriptive text to ensure keyboard/VoiceOver users have the same context.
## 2024-05-24 - Info Icons Tooltip Accessibility
**Learning:** Found multiple bare `Image(systemName: "info.circle")` buttons missing accessibility labels and tooltips, which makes it hard for users to understand what the link opens and impossible for screen readers to navigate properly.
**Action:** Always verify that icon-only buttons include both `.hoverTooltip(...)` for visual context and `.accessibilityLabel(...)` for screen readers. Added these to APISettingsView and CLIProvidersSettingsView.
