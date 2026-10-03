## 2024-05-18 - Missing Tooltip and Accessibility Label on Recommendation Wizard Trigger
**Learning:** Found that generic trigger components like `CheckRecommendationsButton` lacked `.hoverTooltip()` and `.accessibilityLabel()` even though they spawn complex UI wizards. Without contextual labels, screen reader users and those navigating quickly may not grasp the button's action.
**Action:** Add `.hoverTooltip()` and `.accessibilityLabel()` to standalone utility buttons that open major overlays/wizards, ensuring context is provided beyond just the button text itself.
