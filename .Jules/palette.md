## 2024-06-24 - Custom Tooltips Lack Accessibility Labels
**Learning:** The custom `.hoverTooltip()` modifier does not automatically generate accessibility labels for VoiceOver/screen readers on icon-only buttons.
**Action:** Always apply `.accessibilityLabel()` alongside `.hoverTooltip()` for icon-only buttons to ensure they are accessible.
