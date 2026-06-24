import SwiftUI

struct QuickCaptureTitleSection: View {
    let leadingDecorationIcon: String
    let showsNotes: Bool
    @Binding var title: String
    @Binding var tags: [String]
    @Binding var notes: String
    let titleFocused: FocusState<Bool>.Binding
    let onOpenMarkdownEditor: () -> Void

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: leadingDecorationIcon)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("New item", text: $title, axis: .vertical)
                        .font(.title3)
                        .focused(titleFocused)
                        .lineLimit(1...6)
                        .accessibilityIdentifier("quickcapture.title")
                    TagInputView(tags: $tags)
                        .accessibilityIdentifier("quickcapture.tags")
                    if showsNotes {
                        inlineNotesRow
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var inlineNotesRow: some View {
        HStack(alignment: .top, spacing: 6) {
            TextField("Notes", text: $notes, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...8)
                .accessibilityIdentifier("quickcapture.body")
            Button(action: onOpenMarkdownEditor) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Markdown editor")
            .accessibilityIdentifier("item.notes.expand")
        }
        .padding(.top, 2)
    }
}
