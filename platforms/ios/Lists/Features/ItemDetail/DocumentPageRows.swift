import SwiftUI
import UIKit

enum DocumentRailMetrics {
    static let pageHorizontalPadding: CGFloat = ListsSpacing.s4
    static let leadingControlWidth: CGFloat = 28
    static let leadingControlGap: CGFloat = ListsSpacing.s3
    static let textRailOffset: CGFloat = leadingControlWidth + leadingControlGap
}

struct DocumentPageContent: View {
    @Binding var title: String
    @Binding var bodyText: String
    @Binding var tags: [String]
    let item: Item
    let editorMode: MarkdownEditorMode
    let showsLeadingControl: Bool
    let showTagField: Bool
    let tagFocusToken: Int
    let focusBridge: DocumentFocusBridge
    let onToggleDone: () -> Void
    let onToggleFlag: () -> Void
    let onSetPriority: (Item.Priority) -> Void
    let onSetType: (Item.ItemType) -> Void
    let onOpenDetails: () -> Void
    let onAddTags: () -> Void
    let onTitleBeginEditing: () -> Void
    let onRequestDocumentLink: (DocumentLinkEditorSelection) -> Void
    let onRequestAttachment: (DocumentLinkEditorSelection, Data?) -> Void
    let onOpenAttachment: (String) -> Void
    let onOpenLink: (URL) -> Void
    let onFormatRequested: (MarkdownFormatPanelSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DocumentTitleRow(
                title: $title,
                item: item,
                showsLeadingControl: showsLeadingControl,
                monospace: editorMode == .raw,
                onToggleDone: onToggleDone,
                onToggleFlag: onToggleFlag,
                onSetPriority: onSetPriority,
                onSetType: onSetType,
                onOpenDetails: onOpenDetails,
                onAddTags: onAddTags,
                onTitleBeginEditing: onTitleBeginEditing,
                bridge: focusBridge
            )
            DocumentFactStripRow(
                item: item,
                alignsToLeadingControl: showsLeadingControl,
                onOpenDetails: onOpenDetails
            )
            DocumentTagsRow(
                tags: $tags,
                focusToken: tagFocusToken,
                isVisible: !item.tags.isEmpty || showTagField,
                alignsToLeadingControl: showsLeadingControl
            )
            Divider()
                .padding(.top, 4)
            DocumentBodyEditor(
                text: $bodyText,
                mode: editorMode,
                bridge: focusBridge,
                onRequestDocumentLink: onRequestDocumentLink,
                onRequestAttachment: onRequestAttachment,
                onOpenAttachment: onOpenAttachment,
                onOpenLink: onOpenLink,
                onFormatRequested: onFormatRequested
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
    let onToggleFlag: () -> Void
    let onSetPriority: (Item.Priority) -> Void
    let onSetType: (Item.ItemType) -> Void
    let onOpenDetails: () -> Void
    let onAddTags: () -> Void
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
                quickState: DocumentQuickState(
                    flagged: item.flagged,
                    priority: item.priority,
                    type: item.type,
                    tagCount: item.tags.count
                ),
                onToggleFlag: onToggleFlag,
                onSetPriority: onSetPriority,
                onSetType: onSetType,
                onOpenDetails: onOpenDetails,
                onAddTags: onAddTags,
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

    var body: some View {
        if isVisible {
            TagInputView(tags: $tags, focusToken: focusToken)
                .accessibilityIdentifier("document.tags")
                .padding(.leading, alignsToLeadingControl ? DocumentRailMetrics.textRailOffset : 0)
        }
    }
}

struct DocumentFactStripRow: View {
    let item: Item
    let alignsToLeadingControl: Bool
    let onOpenDetails: () -> Void

    var body: some View {
        if hasFacts {
            Button {
                onOpenDetails()
            } label: {
                ItemFactChips(item: item, isOverdue: isOverdue, wraps: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.facts")
            .padding(.leading, alignsToLeadingControl ? DocumentRailMetrics.textRailOffset : 0)
        }
    }

    private var hasFacts: Bool {
        ItemFactChips.hasFacts(for: item)
    }

    private var isOverdue: Bool {
        item.isOverdue()
    }

}
