
## 2024-11-10 - Explicit Accessibility Labels for Custom SwiftUI Tooltips
**Learning:** Custom modifiers like `.hoverTooltip(_)` on icon-only buttons do not automatically provide an accessibility label, leaving screen readers without context.
**Action:** Always pair custom tooltip modifiers on icon-only interactive elements with explicit `.accessibilityLabel(_)` mirroring the intent.
