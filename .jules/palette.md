## 2023-11-06 - Tooltip & Accessibility Pattern
**Learning:** Icon-only buttons often lack accessibility labels and tooltips, which makes them unusable for screen readers and less intuitive for mouse users.
**Action:** When adding `.hoverTooltip(_)` for mouse users, always also add `.accessibilityLabel(_)` for screen readers.
