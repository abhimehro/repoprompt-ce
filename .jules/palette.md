## 2025-05-30 - Added hover tooltip to copy button in PreHighlightedCodeBlock
**Learning:** Found an accessibility and UX gap in `PreHighlightedCodeBlock` where the copy button was missing an accessibility label and a hover tooltip, despite these features being present in similar components like `CodeBlockView` and `SyntaxHighlightedCodeBlock`.
**Action:** Always verify that interactive icon-only buttons have hover tooltips and accessibility labels, especially when similar components in the codebase already implement these features.
