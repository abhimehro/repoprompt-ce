## 2025-02-12 - Missing accessibility labels on session row buttons
**Learning:** Found multiple icon-only buttons in `AgentSessionRows.swift` (e.g., pin, rename, stash, trash, restore) that rely solely on `.hoverTooltip()` but lack explicit `.accessibilityLabel()` modifiers for VoiceOver support.
**Action:** Always add `.accessibilityLabel()` alongside `.hoverTooltip()` for icon-only buttons to ensure they are accessible to screen readers.
