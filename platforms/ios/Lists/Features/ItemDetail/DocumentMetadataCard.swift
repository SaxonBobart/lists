import SwiftUI

/// Compact, native label/value rail shared by the on-page property controls.
struct DocumentPropertyRow<Value: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        LabeledContent {
            value()
                .foregroundStyle(.primary)
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .frame(minHeight: 44)
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
            Toggle(isOn: $isOn) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .frame(width: 44, height: 44)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .tint(ListsTokens.accent)
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityIdentifier(identifier)
        }
    }
}

struct DocumentPropertiesSection<Content: View>: View {
    @Binding var isExpanded: Bool
    var summary: String = ""
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
                    if !isExpanded && !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("document.properties.disclosure")
            if isExpanded {
                VStack(alignment: .leading, spacing: 0, content: content)
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


/// Page visibility is local UI preference; it never changes Markdown or item values.
struct DocumentPropertyVisibility: Equatable {
    var selected: Set<String> = []
    var hidden: Set<String> = []

    func shows(_ field: DocumentPropertyKind, active: Bool) -> Bool {
        !hidden.contains(field.rawValue) && (active || selected.contains(field.rawValue))
    }

    mutating func add(_ field: DocumentPropertyKind) {
        selected.insert(field.rawValue)
        hidden.remove(field.rawValue)
    }

    mutating func hide(_ field: DocumentPropertyKind) {
        selected.remove(field.rawValue)
        hidden.insert(field.rawValue)
    }

    static func load(for id: UUID, defaults: UserDefaults = .standard) -> Self {
        Self(selected: Set(defaults.stringArray(forKey: key(id, "selected")) ?? []),
             hidden: Set(defaults.stringArray(forKey: key(id, "hidden")) ?? []))
    }

    func save(for id: UUID, defaults: UserDefaults = .standard) {
        defaults.set(selected.sorted(), forKey: Self.key(id, "selected"))
        defaults.set(hidden.sorted(), forKey: Self.key(id, "hidden"))
    }

    private static func key(_ id: UUID, _ kind: String) -> String {
        "lists.document.properties.\(kind).v1.\(id.uuidString.lowercased())"
    }
}

enum DocumentPropertyKind: String, CaseIterable, Identifiable {
    case flag, priority, tags, date, time, reminder, alarm, repeatRule, earlyReminder
    case allDay, completable, timeZone, history, source
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .flag: "Flag"
        case .priority: "Priority"
        case .tags: "Tags"
        case .date: "Date"
        case .time: "Time"
        case .reminder: "Reminder"
        case .alarm: "Alarm"
        case .repeatRule: "Repeat"
        case .earlyReminder: "Early reminder"
        case .allDay: "All day"
        case .completable: "Completable"
        case .timeZone: "Time zone"
        case .history: "Completion history"
        case .source: "Calendar source"
        }
    }

    var icon: String {
        switch self {
        case .flag: "flag"
        case .priority: "exclamationmark"
        case .tags: "number"
        case .date: "calendar"
        case .time: "clock"
        case .reminder: "bell"
        case .alarm: "alarm"
        case .repeatRule: "repeat"
        case .earlyReminder, .history: "clock.arrow.circlepath"
        case .allDay: "sun.max"
        case .completable: "checkmark.circle"
        case .timeZone: "globe"
        case .source: "calendar.badge.clock"
        }
    }
}

struct DocumentAddPropertyPicker: View {
    let fields: [DocumentPropertyKind]
    let visible: Set<String>
    let hidden: Set<String>
    let unavailable: Set<String>
    let onAdd: (DocumentPropertyKind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(fields) { field in
                        Button {
                            onAdd(field)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(String(localized: field.title), systemImage: field.icon)
                                    if unavailable.contains(field.rawValue) {
                                        Text(field == .earlyReminder ? "Enable a reminder first" : field == .timeZone ? "Set a time first" : "Add a date first")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if visible.contains(field.rawValue) {
                                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                                } else if hidden.contains(field.rawValue) {
                                    Text("Hidden · value kept").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(visible.contains(field.rawValue) || unavailable.contains(field.rawValue))
                        .accessibilityIdentifier("document.property.add.\(field.rawValue.lowercased())")
                    }
                } footer: {
                    Text("Long-press a property to hide it without clearing its value. Time and repeat need a date; early reminders need an enabled reminder.")
                }
                Section {
                    Label("Custom properties are not available yet", systemImage: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("document.property.picker.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
