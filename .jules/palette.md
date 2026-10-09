## 2024-05-14 - Missing accessibilityLabel on hoverTooltip icon-only buttons
**Learning:** Found that custom `.hoverTooltip(_)` modifier on icon-only buttons in SwiftUI does not automatically provide an accessibility label, requiring explicit `.accessibilityLabel(_)` next to it to ensure full screen reader accessibility.
**Action:** Always verify if a button using `.hoverTooltip` (especially icon-only ones) also includes an `.accessibilityLabel`.

## 2024-05-14 - Concise accessibilityLabel with accessibilityHint
**Learning:** Avoid using the exact same long string for both `.accessibilityLabel` and `.accessibilityHint`. A screen reader will read the verbose sentence back-to-back.
**Action:** The `.accessibilityLabel` should be concise (e.g., "Clear selection") while the `.accessibilityHint` can provide the extra, more verbose context.
