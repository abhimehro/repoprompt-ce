## 2024-11-10 - Add missing accessibility labels to icon-only buttons
**Learning:** Found multiple icon-only buttons using `.hoverTooltip()` without any corresponding `.accessibilityLabel()`. Screen readers would have no context for these buttons, making the UI inaccessible for visually impaired users.
**Action:** Always pair `.hoverTooltip()` on icon-only buttons with `.accessibilityLabel()` when writing new UI code.
