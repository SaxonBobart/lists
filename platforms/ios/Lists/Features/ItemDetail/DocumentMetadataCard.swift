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
    case allDay, completable, timeZone, history, source, section, list
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .flag: "Flag"
        case .priority: "Priority"
        case .tags: "Tags"
        case .date: "Date & time"
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
        case .section: "Section"
        case .list: "List"
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
        case .section: "square.dashed"
        case .list: "tray"
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

struct DocumentPropertyToolbar<Controls: View, AddControl: View>: View {
    let usesGrid: Bool
    let accessibilitySize: Bool
    @ViewBuilder let controls: Controls
    @ViewBuilder let addControl: AddControl

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) { controls }
            }
            .scrollIndicators(.hidden)
            addControl
        }
        .padding(.vertical, 4)
    }
}

/// Full-screen destination picker sharing the Home list row and disclosure style.
struct DocumentListHierarchyPicker: View {
    let store: ItemStore
    let selectedListID: String
    let onSelect: (ItemList) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var collapsed = Set(UserDefaults.standard.stringArray(forKey: "sidebar.collapsed.v1") ?? [])

    private var rows: [ListHierarchy.FlatRow] {
        ListHierarchy.flattenedRows(in: store.lists, expanded: { !collapsed.contains($0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button { onSelect(row.list) } label: {
                            SidebarListCellContent(list: row.list, depth: row.depth,
                                hasChildren: row.hasChildren, isCollapsed: collapsed.contains(row.id),
                                count: store.openItemCount(in: row.id))
                            .padding(.vertical, 7).padding(.horizontal, 16)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(row.list.name)
                        .accessibilityValue(row.id == selectedListID ? "Current list" : "")
                        .accessibilityIdentifier("document.listPicker.list.\(row.id.lowercased())")
                        .overlay(alignment: .trailing) {
                            if row.hasChildren {
                                Button {
                                    if collapsed.contains(row.id) { collapsed.remove(row.id) }
                                    else { collapsed.insert(row.id) }
                                    UserDefaults.standard.set(Array(collapsed).sorted(), forKey: "sidebar.collapsed.v1")
                                } label: {
                                    Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(collapsed.contains(row.id) ? "Expand \(row.list.name)" : "Collapse \(row.list.name)")
                                .accessibilityIdentifier("document.listPicker.disclosure.\(row.id.lowercased())")
                                .padding(.trailing, 8)
                            }
                        }
                        if row.id != rows.last?.id { Divider().padding(.leading, 64) }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Move to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("document.listPicker.cancel")
                }
            }
        }
    }
}

struct DocumentCustomPropertyEditor: View {
    let existingProperties: [ItemCustomProperty]
    let onSave: (ItemCustomProperty) -> Void
    let onCancel: () -> Void
    @State private var property: ItemCustomProperty
    @FocusState private var focusedField: Field?
    private enum Field { case name, value }

    init(property: ItemCustomProperty, existingProperties: [ItemCustomProperty],
         onSave: @escaping (ItemCustomProperty) -> Void, onCancel: @escaping () -> Void) {
        _property = State(initialValue: property)
        self.existingProperties = existingProperties
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existingProperties.contains(where: { $0.id == property.id }) ? "Edit property" : "New custom property")
                .font(.headline)
            TextField("Property name", text: $property.name)
                .textFieldStyle(.roundedBorder).focused($focusedField, equals: .name)
                .submitLabel(.next).onSubmit { focusedField = .value }
                .accessibilityIdentifier("document.custom.name")
            TextField("Text value", text: $property.value, axis: .vertical)
                .lineLimit(1...4).textFieldStyle(.roundedBorder).focused($focusedField, equals: .value)
                .accessibilityIdentifier("document.custom.value")
            Text("Text property").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", action: onCancel).frame(minHeight: 44)
                    .accessibilityIdentifier("document.custom.cancel")
                Spacer()
                Button("Save") {
                    property.name = property.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(property)
                }
                .frame(minHeight: 44).disabled(!property.hasValidName(among: existingProperties))
                .accessibilityIdentifier("document.custom.save")
            }
        }.padding(16)
    }
}
