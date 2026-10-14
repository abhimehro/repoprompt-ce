## 2025-10-01 - Missing Accessibility Labels on Icon-Only Copy Buttons
**Learning:** Icon-only buttons used for copying code (e.g., in CodeBlockView) have a hover tooltip but lack explicit screen reader accessibility labels (`.accessibilityLabel`). Screen readers may read out meaningless icon names or nothing.
**Action:** Added `.accessibilityLabel("Copy code to clipboard")` to copy buttons in `CodeBlockView.swift`. Next time, ensure all icon-only interactive elements have `accessibilityLabel` alongside their `hoverTooltip`.
## 2024-10-15 - [Ensure accessibility labels accompany custom tooltips]
**Learning:** In RepoPrompt CE's SwiftUI codebase, the custom `.hoverTooltip(_)` modifier on icon-only buttons does not automatically provide an accessibility label for VoiceOver users.
**Action:** Explicitly include `.accessibilityLabel(_)` alongside `.hoverTooltip(_)` to ensure full screen reader accessibility.
