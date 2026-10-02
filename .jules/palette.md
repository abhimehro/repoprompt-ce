## 2024-10-02 - Custom Modifier Accessibility Disconnect
**Learning:** In RepoPrompt CE, the custom `.hoverTooltip(_)` modifier on icon-only buttons does not automatically provide an accessibility label to VoiceOver.
**Action:** When adding or reviewing icon-only buttons with `.hoverTooltip(_)`, explicitly include `.accessibilityLabel(_)` alongside it to ensure full screen reader accessibility.
