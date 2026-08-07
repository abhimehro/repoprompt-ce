## 2024-08-07 - Add accessibility labels to icon-only buttons
**Learning:** In RepoPrompt CE, applying the custom `.hoverTooltip(_)` modifier to an icon-only SwiftUI Button does not automatically generate an accessibility label for screen readers. Both `.hoverTooltip(_)` and `.accessibilityLabel(_)` must be explicitly applied to ensure accessibility.
**Action:** When adding or auditing icon-only buttons with tooltips, always ensure `.accessibilityLabel(_)` is also present for screen reader support.
