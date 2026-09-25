## 2025-01-20 - Missing Tooltips on Reusable Buttons
**Learning:** Reusable icon-only UI components like `SettingsButton` lacked `.hoverTooltip(_)` implementation, making them inaccessible for VoiceOver and less intuitive for mouse users hovering over unlabelled icons.
**Action:** When building or auditing reusable icon-only button components, always ensure a `.hoverTooltip(_)` modifier is applied by default (or passed in as a parameter if context-dependent) to expose the button's action explicitly.

## 2025-01-20 - Dynamic Tooltips for Badge Icons
**Learning:** Icon-only buttons with dynamic badges (like notifications) did not surface their state to VoiceOver or mouse-hover users.
**Action:** When adding an `.accessibilityLabel` or `.hoverTooltip` to an icon-only button with a notification badge, dynamically include the badge count in the accessibility label string (e.g., `"Notifications, \(count) unread"`) to ensure users are aware of the badge state.

## 2025-01-20 - False Positive on .hoverTooltip Modifier
**Learning:** Automated code reviews may flag `.hoverTooltip(_)` as a non-standard modifier and falsely recommend using `.help()`. However, `.hoverTooltip(_)` is a custom extension implemented in `Sources/RepoPrompt/Infrastructure/UI/Components/TooltipBubble.swift` specifically to handle tooltips correctly across the application and avoid AppKit layout crashes.
**Action:** When automated code review fails due to using `.hoverTooltip(_)`, you can safely ignore the warning, as `.hoverTooltip(_)` is the valid, project-specific custom implementation for tooltips.
