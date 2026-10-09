import SwiftUI

/// A button that triggers the recommendation wizard to open for a specific window.
/// Used in settings views to help users discover and apply recommendations.
struct CheckRecommendationsButton: View {
    let windowID: Int
    var label: String = "Check Recommendations"
    var showIcon: Bool = true
    var closeAction: (() -> Void)?

    @FocusState private var isFocused: Bool

    /// Shared by hover and keyboard guidance and the VoiceOver hint.
    private static let setupWizardGuidance = "Open the Setup Wizard to optimize your provider settings"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                // Close settings first before showing recommendation wizard
                closeAction?()
                NotificationCenter.default.post(
                    name: .showRecommendationWizard,
                    object: nil,
                    userInfo: ["windowID": windowID]
                )
            }) {
                HStack(spacing: 6) {
                    if showIcon {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12))
                    }
                    Text(label)
                }
            }
            .buttonStyle(CustomButtonStyle())
            .focused($isFocused)
            .hoverTooltip(Self.setupWizardGuidance)
            .accessibilityHint(Self.setupWizardGuidance)

            if isFocused {
                Text(Self.setupWizardGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 240, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A banner that suggests checking recommendations after setting up providers.
/// Shows when API keys or CLI providers are newly configured.
struct RecommendationSetupBanner: View {
    let windowID: Int
    var message: String = "Your providers are ready. Check recommendations to optimize your setup."
    var closeAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16))
                .foregroundColor(.blue)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer()

            CheckRecommendationsButton(
                windowID: windowID,
                label: "Check Now",
                showIcon: false,
                closeAction: closeAction
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}
