## 2025-10-01 - Missing Accessibility Labels on Icon-Only Copy Buttons
**Learning:** Icon-only buttons used for copying code (e.g., in CodeBlockView) have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`). Screen readers may read out meaningless icon names or nothing.
**Action:** Added `.accessibilityLabel("Copy code to clipboard")` to copy buttons in `CodeBlockView.swift`. Next time, ensure all icon-only interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.
## 2023-10-26 - Missing Accessibility Labels on Icon-Only Buttons
**Learning:** Some icon-only interactive elements like compact dual action buttons and copy code blocks lack explicit screen reader accessibility labels.
**Action:** Added `.accessibilityLabel` to `CompactDualActionButton`, `PreHighlightedCodeBlock`, and `EnhancedMarkdownView`. Always double-check icon-only buttons for accessibility labels.
