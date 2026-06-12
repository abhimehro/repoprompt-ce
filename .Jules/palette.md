## 2024-06-12 - Icon-only buttons accessibility
**Learning:** Added accessibility hints and labels to icon-only buttons for copying code.
**Action:** Ensure screen readers can interpret button intent.

## 2024-08-01 - Icon-only buttons accessibility across the app
**Learning:** Found multiple instances where icon-only buttons (like attaching images, copying messages, removing context, or previewing) lacked `accessibilityLabel`, which makes it hard for screen readers to navigate complex sidebars and bubbles.
**Action:** When adding standard macOS system icons (SF Symbols) as buttons, always verify if there is accompanying text. If not, `.accessibilityLabel` is required alongside `.hoverTooltip`.
