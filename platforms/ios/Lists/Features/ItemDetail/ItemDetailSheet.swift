import SwiftUI

/// Modal sheet for viewing AND editing an item. Uses SwiftUI `Form` so
/// the chrome (rounded sections, separators, padding, dark mode, dynamic
/// type) is iOS-native.
struct ItemDetailSheet: View {
    let originalItem: Item
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss

    @State private var draft: Item
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var reminderEnabled: Bool
    @State private var showingDeleteConfirm = false

    init(item: Item, store: ItemStore) {
        self.originalItem = item
        self.store = store
        _draft = State(initialValue: item)
        _hasDate = State(initialValue: item.due != nil)
        _hasTime = State(initialValue: item.due != nil && !item.dueAllDay)
        _reminderEnabled = State(initialValue: item.reminder?.enabled ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                dateAndReminderSection
                organisationSection
                if subItemCount > 0 {
                    threadSection
                }
                deleteSection
            }
            .navigationTitle(typeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isDirty)
                }
            }
            .alert("Delete this item?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\"\(draft.title)\" will move to Recently Deleted.")
            }
            .navigationDestination(for: ThreadDestination.self) { dest in
                if let root = store.items.first(where: { $0.id == dest.rootId }) {
                    ThreadView(root: root, store: store)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    draft.done.toggle()
                    draft.completedAt = draft.done ? .now : nil
                } label: {
                    Image(systemName: draft.done ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(draft.done ? Color.accentColor : Color(.tertiaryLabel))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                TextField("Title", text: $draft.title, axis: .vertical)
                    .font(.title3)
                    .lineLimit(1...4)
                    .strikethrough(draft.done, color: Color(.tertiaryLabel))
                    .foregroundStyle(draft.done ? Color.secondary : Color.primary)
            }
            .padding(.vertical, 4)

            if !draft.tags.isEmpty {
                HStack {
                    ForEach(draft.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }
            }

            TextField("Notes", text: $draft.body, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...20)
        }
    }

    private var dateAndReminderSection: some View {
        Section("When") {
            Toggle(isOn: $hasDate) {
                Label("Date", systemImage: "calendar")
            }
            .onChange(of: hasDate) { _, newValue in
                if newValue, draft.due == nil { draft.due = .now }
                if !newValue { draft.due = nil; hasTime = false; reminderEnabled = false }
            }

            if hasDate {
                DatePicker(
                    selection: Binding(
                        get: { draft.due ?? .now },
                        set: { draft.due = $0 }
                    ),
                    displayedComponents: hasTime ? [.date, .hourAndMinute] : .date
                ) {
                    Label("Due", systemImage: "clock.fill")
                }
                Toggle(isOn: $hasTime) {
                    Label("Include time", systemImage: "clock")
                }
                .onChange(of: hasTime) { _, newValue in
                    draft.dueAllDay = !newValue
                }
                Toggle(isOn: $reminderEnabled) {
                    Label("Remind me", systemImage: "bell")
                }
                .onChange(of: reminderEnabled) { _, newValue in
                    draft.reminder = Reminder(enabled: newValue, early: draft.reminder?.early)
                }
            }
        }
    }

    private var organisationSection: some View {
        Section("Details") {
            Toggle(isOn: $draft.flagged) {
                Label("Flag", systemImage: "flag.fill")
            }
            Picker(selection: $draft.priority) {
                ForEach(Item.Priority.allCases, id: \.self) { p in
                    Text(displayName(for: p)).tag(p)
                }
            } label: {
                Label("Priority", systemImage: "exclamationmark")
            }
            Picker(selection: $draft.listId) {
                ForEach(activeLists, id: \.id) { list in
                    HStack {
                        Image(systemName: list.icon)
                            .foregroundStyle(ListsTokens.listColor(list.color))
                        Text(list.name)
                    }
                    .tag(list.id)
                }
            } label: {
                Label("List", systemImage: "tray")
            }
            if let section = draft.section {
                LabeledContent {
                    Text(section).foregroundStyle(.secondary)
                } label: {
                    Label("Section", systemImage: "square.stack")
                }
            }
        }
    }

    private var threadSection: some View {
        Section {
            NavigationLink(value: ThreadDestination(rootId: draft.id)) {
                Label("Thread view", systemImage: "list.bullet.indent")
                    .badge(subitemsValue)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete Item", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Computed

    private var typeTitle: String {
        switch draft.type {
        case .task: return "Task"
        case .habit: return "Habit"
        case .note: return "Note"
        }
    }

    private var isDirty: Bool { draft != originalItem }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private var subItemCount: Int {
        store.items.filter { $0.parentId == draft.id && $0.deletedAt == nil }.count
    }

    private var subitemsValue: String {
        let count = subItemCount
        if count == 0 { return "None" }
        let done = store.items.filter { $0.parentId == draft.id && $0.done && $0.deletedAt == nil }.count
        return "\(done)/\(count)"
    }

    private func displayName(for p: Item.Priority) -> String {
        switch p {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    // MARK: - Actions

    private func save() {
        Task {
            try? await store.update(draft)
            dismiss()
        }
    }

    private func delete() {
        Task {
            try? await store.softDelete(draft.id)
            dismiss()
        }
    }
}
