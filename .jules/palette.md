## 2026-07-31 - Custom Tooltips Lack Accessibility Labels
**Learning:** In RepoPrompt CE, applying the custom `.hoverTooltip(_)` modifier to an icon-only SwiftUI Button does not automatically generate an accessibility label for screen readers.
**Action:** Both `.hoverTooltip(_)` and `.accessibilityLabel(_)` must be explicitly applied to ensure accessibility for icon-only buttons.
