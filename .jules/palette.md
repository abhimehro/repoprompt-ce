## 2025-07-07 - VoiceOver Labels for hoverTooltip
**Learning:** The custom `.hoverTooltip(_)` modifier in this codebase provides visual tooltips but does not automatically expose those labels to the accessibility tree. Icon-only buttons using `.hoverTooltip` remain inaccessible to VoiceOver (often just read as "Button").
**Action:** When adding or encountering icon-only buttons with `.hoverTooltip`, explicitly add `.accessibilityLabel(_)` with the same or a descriptive string to ensure WCAG 'Label in Name' compliance.
