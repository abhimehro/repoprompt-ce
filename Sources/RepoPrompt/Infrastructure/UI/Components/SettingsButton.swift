import SwiftUI

struct SettingsButton<Content: View>: View {
    @Binding var showPopover: Bool
    let icon: String
    let contentBuilder: () -> Content
    @State private var isHovered = false

    init(showPopover: Binding<Bool>, icon: String, @ViewBuilder content: @escaping () -> Content) {
        _showPopover = showPopover
        self.icon = icon
        contentBuilder = content
    }

    var body: some View {
        Button(action: {
            showPopover.toggle()
        }) {
            ZStack {
                Color.clear

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isHovered ? .primary : .secondary)
            }
            .frame(width: 32, height: 32)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Settings")
        .onHover { hovering in
            isHovered = hovering
        }
        .sheet(isPresented: $showPopover) {
            contentBuilder()
                .interactiveDismissDisabled(false)
                .id(showPopover) // Force new instance when reopening
        }
    }
}
