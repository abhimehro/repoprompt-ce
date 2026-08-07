## 2026-08-06 - Accessibility Label Discrepancy
**Learning:** Custom '.hoverTooltip(_)' modifier does not automatically create accessibility labels for icon-only buttons.
**Action:** Ensure '.accessibilityLabel(_)' is explicitly applied alongside '.hoverTooltip(_)' for all icon-only interactive elements to maintain screen reader accessibility.

## 2026-08-07 - Add accessibility labels to notification row icon buttons
**Learning:** Applying `.hoverTooltip(_)` to an icon-only SwiftUI Button does not automatically generate an accessibility label for screen readers. Both `.hoverTooltip(_)` and `.accessibilityLabel(_)` must be explicitly applied.
**Action:** When adding or auditing icon-only buttons with tooltips, always ensure `.accessibilityLabel(_)` is also present for screen reader support.
