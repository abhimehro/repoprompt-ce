## 2024-06-12 - Icon-only buttons accessibility
**Learning:** Added accessibility hints and labels to icon-only buttons for copying code.
**Action:** Ensure screen readers can interpret button intent.

## 2024-08-01 - Icon-only buttons accessibility across the app
**Learning:** Found multiple instances where icon-only buttons (like attaching images, copying messages, removing context, or previewing) lacked `accessibilityLabel`, which makes it hard for screen readers to navigate complex sidebars and bubbles.
**Action:** When adding standard macOS system icons (SF Symbols) as buttons, always verify if there is accompanying text. If not, `.accessibilityLabel` is required alongside `.hoverTooltip`.

## 2024-10-24 - Implicit vs Explicit Accessibility Labels
**Learning:** Found several icon-only buttons across UI components (e.g., in `CompactDualActionButton`, `DualClickPopoverButton`, `NotificationsButtonView`, `SettingsButton`, and `WorkspaceApprovalOverlayView`) that lacked `accessibilityLabel`. The use of custom styles can sometimes hide standard button properties.
**Action:** Always add `.accessibilityLabel` to buttons containing only images or using custom label-less styles to ensure VoiceOver provides a clear description of the action.
