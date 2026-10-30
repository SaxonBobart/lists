import SwiftUI
import UIKit

enum DocumentRailMetrics {
    static let pageHorizontalPadding: CGFloat = ListsSpacing.s4
    static let leadingControlWidth: CGFloat = 28
    static let leadingControlGap: CGFloat = ListsSpacing.s3
    static let textRailOffset: CGFloat = leadingControlWidth + leadingControlGap
}

struct DocumentPageContent<Properties: View>: View {
    @Binding var title: String
    @Binding var bodyText: String
    @Binding var tags: [String]
    let item: Item
    let attachmentStore: ItemStore
    let editorMode: MarkdownEditorMode
    let showsLeadingControl: Bool
    let showTagField: Bool
    let tagFocusToken: Int
    let focusBridge: DocumentFocusBridge
    let onToggleDone: () -> Void
    let onTitleBeginEditing: () -> Void
    let onRequestDocumentLink: (DocumentLinkEditorSelection) -> Void
    let onRequestAttachment: (DocumentLinkEditorSelection, Data?) -> Void
    let onOpenAttachment: (String) -> Void
    let onOpenLink: (URL) -> Void
    let onFormatRequested: (MarkdownFormatPanelSession) -> Void
    let onTableSelectionChanged: (Bool) -> Void
    let onCopySelectionChanged: (Bool) -> Void
    let properties: Properties
    var onEditTags: () -> Void = {}
    var onEndEditingTags: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DocumentTitleRow(
                title: $title,
                item: item,
                showsLeadingControl: showsLeadingControl,
                monospace: editorMode == .raw,
                onToggleDone: onToggleDone,
                onTitleBeginEditing: onTitleBeginEditing,
                bridge: focusBridge
            )
            DocumentTagsRow(tags: $tags, focusToken: tagFocusToken,
                            isVisible: showTagField, alignsToLeadingControl: showsLeadingControl,
                            onEdit: onEditTags, onEndEditing: onEndEditingTags)
            Divider()
            properties
            DocumentBodyEditor(
                text: $bodyText,
                documentID: item.id,
                mode: editorMode,
                bridge: focusBridge,
                onRequestDocumentLink: onRequestDocumentLink,
                onRequestAttachment: onRequestAttachment,
                onOpenAttachment: onOpenAttachment,
                onOpenLink: onOpenLink,
                onFormatRequested: onFormatRequested,
                onTableSelectionChanged: onTableSelectionChanged,
                onCopySelectionChanged: onCopySelectionChanged
            )

        }
        .padding(.horizontal, DocumentRailMetrics.pageHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 48)
    }
}

struct DocumentTitleRow: View {
    @Binding var title: String
    let item: Item
    let showsLeadingControl: Bool
    let monospace: Bool
    let onToggleDone: () -> Void
    let onTitleBeginEditing: () -> Void
    let bridge: DocumentFocusBridge

    var body: some View {
        HStack(alignment: .top, spacing: DocumentRailMetrics.leadingControlGap) {
            if showsLeadingControl {
                doneCheckbox
            }
            DocumentTitleField(
                text: $title,
                textColor: UIColor(item.isComplete ? ListsTokens.Foreground.secondary
                                                   : ListsTokens.Foreground.primary),
                monospace: monospace,
                placeholder: item.type.titlePlaceholder,
                onBeginEditing: onTitleBeginEditing,
                bridge: bridge
            )
        }
    }

    private var doneCheckbox: some View {
        Button {
            onToggleDone()
        } label: {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(item.done ? ListsTokens.accent : ListsTokens.Foreground.tertiary)
                .frame(width: DocumentRailMetrics.leadingControlWidth, height: 28, alignment: .leading)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.done ? "Mark not done" : "Mark done")
        .accessibilityIdentifier("document.checkbox")
    }
}

struct DocumentTagsRow: View {
    @Binding var tags: [String]
    let focusToken: Int
    let isVisible: Bool
    let alignsToLeadingControl: Bool
    var onEdit: () -> Void = {}
    var onEndEditing: () -> Void = {}

    var body: some View {
        if isVisible {
            TagInputView(tags: $tags, focusToken: focusToken, onEditingChanged: { editing in
                if !editing { onEndEditing() }
            })
                .accessibilityIdentifier("document.tags")
                .padding(.leading, alignsToLeadingControl ? DocumentRailMetrics.textRailOffset : 0)
        } else if !tags.isEmpty {
            Button(action: onEdit) {
                Text(tags.map { "#" + $0 }.joined(separator: " "))
                    .font(.subheadline).foregroundStyle(ListsTokens.tagAccent)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit tags")
            .accessibilityValue(tags.joined(separator: ", "))
            .accessibilityIdentifier("document.tags.edit")
            .padding(.leading, alignsToLeadingControl ? DocumentRailMetrics.textRailOffset : 0)
        }
    }
}
