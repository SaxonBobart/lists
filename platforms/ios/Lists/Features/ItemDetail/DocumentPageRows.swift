import SwiftUI
import UIKit

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
            DocumentBodyEditor(text: $bodyText, mode: editorMode, bridge: focusBridge)
        }
        .padding(.horizontal, 16)
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
    let bridge: DocumentFocusBridge

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsLeadingControl {
                doneCheckbox
            }
            DocumentTitleField(
                text: $title,
                textColor: UIColor(item.isComplete ? ListsTokens.Foreground.secondary
                                                   : ListsTokens.Foreground.primary),
                monospace: monospace,
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
                .frame(width: 28, height: 28, alignment: .leading)
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
                .padding(.leading, alignsToLeadingControl ? 40 : 0)
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
            // Align under the title text: 28pt rail + 12pt gap when a checkbox
            // is shown; flush at the margin for notes and plain events.
            .padding(.leading, alignsToLeadingControl ? 40 : 0)
        }
    }

    private var hasFacts: Bool {
        ItemFactChips.hasFacts(for: item)
    }

    private var isOverdue: Bool {
        item.isOverdue()
    }

}
