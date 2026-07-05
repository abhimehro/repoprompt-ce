import SwiftUI

struct CheckboxView: View {
    let isChecked: CheckboxState
    let action: () -> Void
    @State private var isHovering = false

    /// Precomputed shapes
    private let backgroundShape = RoundedRectangle(cornerRadius: 4)
        .fill(Color.secondary.opacity(0.2))
    /*
     private static let borderShape = RoundedRectangle(cornerRadius: 4)
     	.stroke(Color.secondary.opacity(0.5), lineWidth: 1)
      */

    var body: some View {
        Button(action: action) {
            Image(systemName: checkboxImageName)
                .accessibilityLabel("Checkbox")
                .accessibilityValue(isChecked == .checked ? "Checked" : isChecked == .unchecked ? "Unchecked" : "Mixed")
                .foregroundColor(checkboxColor)
                .frame(width: 20, height: 20)
                .background(isHovering ? backgroundShape : nil)
            // .overlay(isHovering ? Self.borderShape : nil)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var checkboxImageName: String {
        switch isChecked {
        case .checked:
            "checkmark.square"
        case .unchecked:
            "square"
        case .mixed:
            "minus.square"
        }
    }

    private var checkboxColor: Color {
        switch isChecked {
        case .checked, .mixed:
            .accentColor
        case .unchecked:
            isHovering ? .primary : .secondary
        }
    }
}
