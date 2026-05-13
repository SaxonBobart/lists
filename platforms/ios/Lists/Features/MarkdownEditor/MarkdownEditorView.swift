import SwiftUI

/// Full-screen Markdown editor. Hosted via `.fullScreenCover` from
/// `ItemDetailSheet` and `QuickCaptureSheet` (and, later, the tree
/// view). The binding is the plain-text markdown source. A glass-style
/// segmented control in the toolbar swaps between Bear-style **Live**
/// rendering and SF Mono **Raw** source view.
struct MarkdownEditorView: View {
    @Binding var text: String
    let title: String?
    let onDone: () -> Void

    @State private var mode: MarkdownEditorMode = .live

    var body: some View {
        NavigationStack {
            MarkdownTextView(text: $text, mode: mode)
                .background(ListsTokens.Background.base)
                .navigationTitle(displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onDone() } label: {
                            Image(systemName: "xmark").accessibilityLabel("Close")
                        }
                        .accessibilityIdentifier("markdown.close")
                    }
                    ToolbarItem(placement: .principal) {
                        modePicker
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { onDone() } label: {
                            Image(systemName: "checkmark").accessibilityLabel("Done")
                        }
                        .accessibilityIdentifier("markdown.done")
                    }
                }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            Text("Live").tag(MarkdownEditorMode.live).accessibilityIdentifier("markdown.mode.live")
            Text("Raw").tag(MarkdownEditorMode.raw).accessibilityIdentifier("markdown.mode.raw")
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 160)
        .glassEffect(.regular, in: Capsule())
        .accessibilityIdentifier("markdown.modePicker")
    }

    private var displayTitle: String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Notes" : trimmed
    }
}
