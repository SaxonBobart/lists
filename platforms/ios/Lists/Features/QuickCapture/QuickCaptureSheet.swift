import SwiftUI

/// Bottom sheet for adding a new task quickly. Uses SwiftUI `Form` so the
/// chrome (rounded sections, separators, padding, keyboard handling) is
/// iOS-native.
struct QuickCaptureSheet: View {
    let store: ItemStore
    let defaultListId: String
    let defaultSection: String?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    @State private var title: String = ""
    @State private var listId: String
    @State private var hasDate: Bool = false
    @State private var due: Date = .now
    @State private var hasTime: Bool = false
    @State private var flagged: Bool = false
    @State private var priority: Item.Priority = .none
    @State private var section: String

    init(store: ItemStore, defaultListId: String = ItemList.inboxId, defaultSection: String? = nil) {
        self.store = store
        self.defaultListId = defaultListId
        self.defaultSection = defaultSection
        _listId = State(initialValue: defaultListId)
        _section = State(initialValue: defaultSection ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "circle")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, alignment: .center)
                        TextField("New task", text: $title, axis: .vertical)
                            .font(.title3)
                            .focused($titleFocused)
                            .lineLimit(1...6)
                    }
                    .padding(.vertical, 4)
                }

                Section("When") {
                    Toggle(isOn: $hasDate) {
                        Label("Date", systemImage: "calendar")
                    }
                    if hasDate {
                        DatePicker(
                            selection: $due,
                            displayedComponents: hasTime ? [.date, .hourAndMinute] : .date
                        ) {
                            Label("Due", systemImage: "clock.fill")
                        }
                        Toggle(isOn: $hasTime) {
                            Label("Include time", systemImage: "clock")
                        }
                    }
                }

                Section("Details") {
                    Toggle(isOn: $flagged) {
                        Label("Flag", systemImage: "flag.fill")
                    }
                    Picker(selection: $priority) {
                        ForEach(Item.Priority.allCases, id: \.self) { p in
                            Text(displayName(for: p)).tag(p)
                        }
                    } label: {
                        Label("Priority", systemImage: "exclamationmark")
                    }
                    Picker(selection: $listId) {
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
                    HStack {
                        Label("Section", systemImage: "square.stack")
                        Spacer()
                        TextField("None", text: $section)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .submitLabel(.done)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { add() }
                        .fontWeight(.semibold)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear {
                // Tiny delay so the focus survives the sheet's appearance animation.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    titleFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private func displayName(for p: Item.Priority) -> String {
        switch p {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    private func add() {
        let listType = store.lists.first(where: { $0.id == listId })?.defaultItemType ?? .task
        let trimmedSection = section.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = Item(
            type: listType,
            title: trimmedTitle,
            listId: listId,
            section: trimmedSection.isEmpty ? nil : trimmedSection,
            due: hasDate ? due : nil,
            dueAllDay: hasDate && !hasTime,
            priority: priority,
            flagged: flagged,
            frequency: listType == .habit ? .daily : nil,
            goalPerCycle: 1,
            showStreak: listType == .habit
        )
        Task {
            try? await store.add(item)
            dismiss()
        }
    }
}
