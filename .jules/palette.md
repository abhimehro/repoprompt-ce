## 2023-10-24 - Missing Accessibility Labels on Icon-Only Buttons
**Learning:** Icon-only buttons with hover tooltips (`.hoverTooltip`) often miss explicit screen reader labels (`.accessibilityLabel`), making them inaccessible to visually impaired users.
**Action:** When adding `.hoverTooltip` to icon-only buttons, always ensure an equivalent `.accessibilityLabel` is also added so screen readers provide meaningful context.
