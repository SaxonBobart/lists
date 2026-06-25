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
    let habitsPluginEnabled: Bool
    let onSetType: (Item.ItemType) -> Void
    let onBeginParentMove: () -> Void
    let onShowSectionPicker: () -> Void
    let onSelectList: (ItemList) -> Void

    var body: some View {
        Section("Organization") {
            typeRow

            if type == .event {
                Toggle(isOn: $completable) {
                    DetailFormRowLabel(title: "Checkbox", subtitle: nil, systemImage: "checkmark.circle")
                }
                .tint(.green)
                .accessibilityIdentifier("document.completable")
            }

            Toggle(isOn: $flagged) {
                DetailFormRowLabel(
                    title: "Flag",
                    subtitle: nil,
                    systemImage: flagged ? "flag.fill" : "flag",
                    iconColor: flagged ? ListsTokens.Semantic.warning : nil
                )
            }
            .tint(.green)
            .accessibilityIdentifier("document.flag")

            ItemPriorityPickerRow(priority: $priority)
                .accessibilityIdentifier("document.priority")

            if showsHierarchyMoveControl {
                parentRow
            }

            Button {
                onShowSectionPicker()
            } label: {
                DetailFormDisclosureRowLabel(
                    title: "Section",
                    value: sectionName ?? "None",
                    systemImage: "square.dashed"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.section")

            DetailFormListMenuRow(
                lists: lists,
                selectedListId: selectedListId,
                selectedList: selectedList,
                onSelect: onSelectList
            )
            .accessibilityIdentifier("document.list")
        }
    }

    private var typeRow: some View {
        Menu {
            Section {
                ForEach(itemTypePolicy.compactMenuSystemTypes, id: \.self) { type in
                    typeButton(type)
                }
            }
            if !itemTypePolicy.compactMenuCorePluginTypes.isEmpty {
                Section {
                    ForEach(itemTypePolicy.compactMenuCorePluginTypes, id: \.self) { type in
                        typeButton(type)
                    }
                }
            }
        } label: {
            DetailFormPickerRowLabel(
                title: "Type",
                value: typeDisplayName,
                systemImage: type.documentGlyph
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("document.type")
    }

    private var itemTypePolicy: ItemTypePolicy {
        ItemTypePolicy(habitsEnabled: habitsPluginEnabled)
    }

    private func typeButton(_ itemType: Item.ItemType) -> some View {
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
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("document.parent")
    }
}
