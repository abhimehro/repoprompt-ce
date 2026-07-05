## 2026-07-04 - Accessibility in Custom UI Components
**Learning:** Found multiple icon-only custom UI components (like checkboxes, close buttons, and copy buttons) missing standard `.accessibilityLabel` modifiers, degrading the experience for screen reader users. SwiftUI custom view modifiers do not implicitly generate accessibility tags.
**Action:** Always verify accessibility labels on icon-only interactive elements and custom interactive wrappers in SwiftUI.
