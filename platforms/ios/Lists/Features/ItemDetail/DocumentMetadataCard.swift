import SwiftUI

struct DocumentMetadataCard: View {
    let type: Item.ItemType
    let typeDisplayName: String
    @Binding var completable: Bool
    @Binding var flagged: Bool
    @Binding var priority: Item.Priority
    let showsHierarchyMoveControl: Bool
    let parentMoveLabel: String
    let sectionName: String?
    let lists: [ItemList]
    let selectedListId: String
    let selectedList: ItemList?
    let onSetType: (Item.ItemType) -> Void
    let onBeginParentMove: () -> Void
    let onShowSectionPicker: () -> Void
    let onSelectList: (ItemList) -> Void

    var body: some View {
        DocumentOptionsCard {
            typeRow

            if type == .event {
                Divider()
                Toggle(isOn: $completable) {
                    DetailFormRowLabel(title: "Completable", subtitle: nil, systemImage: "checkmark.circle")
                }
                .tint(.green)
                .padding(.vertical, 7)
                .accessibilityIdentifier("document.completable")
            }

            Divider()

            Toggle(isOn: $flagged) {
                DetailFormRowLabel(title: "Flag", subtitle: nil, systemImage: "flag")
            }
            .tint(.green)
            .padding(.vertical, 7)
            .accessibilityIdentifier("document.flag")

            Divider()

            ItemPriorityPickerRow(priority: $priority)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
                .accessibilityIdentifier("document.priority")

            if showsHierarchyMoveControl {
                Divider()
                parentRow
            }

            Divider()

            Button {
                onShowSectionPicker()
            } label: {
                DetailFormDisclosureRowLabel(
                    title: "Section",
                    value: sectionName,
                    systemImage: "square.dashed"
                )
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.section")

            Divider()

            DetailFormListMenuRow(
                lists: lists,
                selectedListId: selectedListId,
                selectedList: selectedList,
                onSelect: onSelectList
            )
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .accessibilityIdentifier("document.list")
        }
    }

    private var typeRow: some View {
        Menu {
            ForEach([Item.ItemType.task, .note, .event], id: \.self) { itemType in
                Button {
                    onSetType(itemType)
                } label: {
                    if itemType == type {
                        Label(itemType.documentDisplayName, systemImage: "checkmark")
                    } else {
                        Label(itemType.documentDisplayName, systemImage: itemType.documentGlyph)
                    }
                }
            }
        } label: {
            DetailFormPickerRowLabel(
                title: "Type",
                value: typeDisplayName,
                systemImage: type.documentGlyph
            )
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("document.type")
    }

    private var parentRow: some View {
        Button {
            onBeginParentMove()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.indent")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .center)
                Text("Parent")
                    .foregroundStyle(.primary)
                Spacer()
                Text(parentMoveLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .font(.footnote)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("document.parent")
    }
}
