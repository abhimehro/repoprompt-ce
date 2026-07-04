//
//  PreHighlightedCodeBlock.swift
//  RepoPrompt
//
//  Created by Eric Provencher on 2025-05-30.
//

import AppKit
import SwiftUI

/// Displays a **pre-compiled** attributed string representing a code block,
/// adds background/border to match other code blocks and overlays a copy
/// button.  No additional parsing or highlighting is performed.
struct PreHighlightedCodeBlock: View {
    let attributedString: NSAttributedString
    let allowTextSelection: Bool

    @State private var isCopyHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main attributed text
            AttributedTextView(
                attributedString: attributedString,
                isEditable: false,
                allowsTextSelection: allowTextSelection
            )
            .padding(8)
            .background(BubbleColors.codeBlockBackground)
            .cornerRadius(8)

            // Copy-to-clipboard button
            Button(action: copyCode) {
                Image(systemName: "doc.on.clipboard")
                .accessibilityLabel("Copy to clipboard")
                    .foregroundColor(
                        isCopyHovering
                            ? BubbleColors.copyIconHover
                            : BubbleColors.copyIconNormal
                    )
            }
            .buttonStyle(.plain)
            .padding(8)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isCopyHovering = hovering
                }
            }
        }
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(attributedString.string, forType: .string)
    }
}
