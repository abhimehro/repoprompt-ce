## 2024-05-14 - Missing Accessibility Labels on Tooltip Buttons
**Learning:** Icon-only buttons with `.hoverTooltip()` in SwiftUI don't automatically generate an `.accessibilityLabel()` for screen readers.
**Action:** When adding `.hoverTooltip()` to icon-only buttons, always ensure a corresponding `.accessibilityLabel()` is applied, especially for non-obvious UI elements.
