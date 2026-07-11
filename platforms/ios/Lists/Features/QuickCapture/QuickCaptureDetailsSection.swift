import SwiftUI

struct QuickCaptureDetailsSection: View {
    let showsCompletable: Bool
    @Binding var completable: Bool
    @Binding var flagged: Bool
    @Binding var priority: Item.Priority
    @Binding var tags: [String]
    @Binding var section: String?
    @Binding var listId: String
    let activeLists: [ItemList]
    let selectedList: ItemList?
    let sectionDisplayName: (String) -> String?
    let onShowSectionPicker: () -> Void

    var body: some View {
        Section("Organization") {
            if showsCompletable {
                Toggle(isOn: $completable) {
                    DetailFormRowLabel(
                        title: "Checkbox",
                        subtitle: completable ? "Behaves like a task - can go overdue" : nil,
                        systemImage: "checkmark.circle"
                    )
                }
                .tint(.green)
                .accessibilityIdentifier("quickcapture.completable")
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
            .accessibilityIdentifier("quickcapture.flag")

            ItemPriorityPickerRow(priority: $priority)
                .accessibilityIdentifier("quickcapture.priority")

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "number")
                    .font(.body)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .center)
                    .padding(.top, 1)

                TagInputView(tags: $tags)
                    .accessibilityIdentifier("quickcapture.tags")
            }
            .padding(.vertical, 2)

            Button(action: onShowSectionPicker) {
                DetailFormDisclosureRowLabel(
                    title: "Section",
                    value: section.flatMap(sectionDisplayName) ?? "None",
                    systemImage: "square.dashed"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quickcapture.section")

            DetailFormListMenuRow(
                lists: activeLists,
                selectedListId: listId,
                selectedList: selectedList
            ) { list in
                if listId != list.id {
                    listId = list.id
                    section = nil
                }
            }
            .accessibilityIdentifier("quickcapture.list")
        }
    }
}
