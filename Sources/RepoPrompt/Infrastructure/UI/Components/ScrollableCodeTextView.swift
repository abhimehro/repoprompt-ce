//
//  ScrollableCodeTextView.swift
//  RepoPrompt
//
//  A TextKit-based scrollable text view for large code/output content.
//  Uses NSTextView with fixed max height and internal scrolling.
//

import AppKit
import SwiftUI

/// A scrollable monospace text view with a fixed max height.
/// Uses NSTextView (TextKit) for efficient rendering of large text content.
struct ScrollableCodeTextView: NSViewRepresentable {
    let text: String
    let maxHeight: CGFloat

    @ObservedObject private var fontScale = FontScaleManager.shared
    @Environment(\.colorScheme) private var colorScheme

    init(text: String, maxHeight: CGFloat = 300) {
        self.text = text
        self.maxHeight = maxHeight
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false

        // Configure for horizontal scrolling (no line wrapping)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false

        // Small padding inside text view
        textView.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update font
        let fontSize = max(fontScale.preset.rawValue - 2, 9)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Update text color based on color scheme
        let textColor: NSColor = colorScheme == .dark ? .white : .labelColor

        // Only update if text changed to avoid unnecessary redraws
        if textView.string != text {
            textView.string = text
        }

        // Apply font and color to entire text
        textView.font = font
        textView.textColor = textColor

        // Recalculate content size
        textView.sizeToFit()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {}
}

/// SwiftUI wrapper that adds max height constraint and background styling
struct ScrollableCodeBlock: View {
    let content: String
    let maxHeight: CGFloat
    let showCopyButton: Bool

    @State private var isCopyHovering = false
    @Environment(\.colorScheme) private var colorScheme

    init(content: String, maxHeight: CGFloat = 300, showCopyButton: Bool = true) {
        self.content = content
        self.maxHeight = maxHeight
        self.showCopyButton = showCopyButton
    }

    private var lineCount: Int {
        #if DEBUG
            let diagnosticsStartMS = AgentTextDerivationPerfDiagnostics.start()
        #endif
        let derivedLineCount = content.components(separatedBy: "\n").count
        #if DEBUG
            AgentTextDerivationPerfDiagnostics.record(
                source: .scrollableCodeHeight,
                startMS: diagnosticsStartMS,
                text: content,
                lineCount: derivedLineCount,
                displayedLineCount: derivedLineCount,
                didSplitFullArray: true
            )
        #endif
        return derivedLineCount
    }

    /// Calculate intrinsic height based on line count, capped at maxHeight
    private var calculatedHeight: CGFloat {
        let lineHeight: CGFloat = 16 // Approximate line height for monospace
        let padding: CGFloat = 16 // Top + bottom padding
        let intrinsicHeight = CGFloat(lineCount) * lineHeight + padding
        return min(intrinsicHeight, maxHeight)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollableCodeTextView(text: content, maxHeight: maxHeight)
                .frame(height: calculatedHeight)

            if showCopyButton {
                copyButton
            }
        }
        .background(BubbleColors.codeBlockBackground)
        .cornerRadius(4)
    }

    private var copyButton: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
        }) {
            Image(systemName: "doc.on.clipboard")
                .foregroundColor(isCopyHovering ? BubbleColors.copyIconHover : BubbleColors.copyIconNormal)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isCopyHovering = hovering
            }
        }
        .hoverTooltip("Copy to clipboard")
        .accessibilityLabel("Copy to clipboard")
        .padding(4)
    }
}

// MARK: - Preview

#if DEBUG
    struct ScrollableCodeTextView_Previews: PreviewProvider {
        static var sampleCode: String {
            (1 ... 50).map { "Line \($0): let value = computeSomething(input: \($0))" }.joined(separator: "\n")
        }

        static var previews: some View {
            VStack(spacing: 16) {
                // Short content - should size to content
                ScrollableCodeBlock(
                    content: "let x = 42\nlet y = 100",
                    maxHeight: 200
                )

                // Long content - should cap at maxHeight with scroll
                ScrollableCodeBlock(
                    content: sampleCode,
                    maxHeight: 200
                )
            }
            .padding()
            .frame(width: 500)
        }
    }
#endif
