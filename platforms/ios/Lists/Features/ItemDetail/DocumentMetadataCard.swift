import SwiftUI

/// Compact, native label/value rail shared by the on-page property controls.
struct DocumentPropertyRow<Value: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .frame(minHeight: 34)
        .contentShape(Rectangle())
    }
}

struct DocumentPropertyToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let identifier: String

    var body: some View {
        DocumentPropertyRow(title: title, systemImage: systemImage) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .tint(ListsTokens.accent)
                .accessibilityIdentifier(identifier)
        }
    }
}

struct DocumentPropertiesSection<Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.smooth) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.caption.weight(.semibold))
                    Text("Details").font(.subheadline.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("document.properties.disclosure")
            if isExpanded {
                VStack(alignment: .leading, spacing: 2, content: content)
                    .buttonStyle(.plain)
                    .tint(.primary)
            }
        }
    }
}

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
