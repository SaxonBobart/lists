import SwiftUI

/// Sheet for creating a new list OR editing an existing one. Custom
/// scroll-based layout (not `Form`) so the cards, big icon preview, and
/// color/icon grids can match the design exactly.
struct ListEditSheet: View {
    private enum Operation {
        case adding
        case saving
        case deleting

        var errorTitle: String {
            switch self {
            case .adding: "Couldn’t Add List"
            case .saving: "Couldn’t Save List"
            case .deleting: "Couldn’t Delete List"
            }
        }
    }

    private struct OperationFailure {
        let operation: Operation
        let message: String
    }

    let existing: ItemList?
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameFocused: Bool

    @State private var name: String
    @State private var icon: String
    @State private var color: ItemList.ListColor
    @State private var listType: ListEditType
    @State private var parentId: String?
    @State private var showingDeleteConfirm = false
    @State private var showingParentPicker = false
    @State private var activeOperation: Operation?
    @State private var operationFailure: OperationFailure?
    @State private var deleteNeedsRetry = false

    @State private var emojiInput: String = ""
    @State private var emojiFieldFocused: Bool = false

    /// `initialParentId` only applies when creating a new list — it
    /// pre-fills the Parent picker so "+ New sub-list here" lands the new
    /// list under the right parent. Ignored when editing (`existing != nil`).
    init(existing: ItemList? = nil, store: ItemStore, initialParentId: String? = nil) {
        self.existing = existing
        self.store = store
        _name = State(initialValue: existing?.name ?? "")
        _icon = State(initialValue: existing?.icon ?? "list.bullet")
        _color = State(initialValue: existing?.color ?? .blue)
        _listType = State(initialValue: ListEditType.from(existing))
        _parentId = State(initialValue: existing?.parentId ?? initialParentId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    iconAndNameCard
                    listTypeCard
                    parentRowCard
                    colorGridCard
                    iconGridCard
                    if existing != nil {
                        deleteButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .disabled(activeOperation != nil)
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(existing == nil ? "New List" : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel")
                    }
                    .disabled(activeOperation != nil || deleteNeedsRetry)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { save() } label: {
                        Image(systemName: "checkmark")
                            .accessibilityLabel(existing == nil ? "Add" : "Save")
                    }
                    .disabled(
                        trimmedName.isEmpty
                            || activeOperation != nil
                            || deleteNeedsRetry
                    )
                }
            }
            .alert("Delete this list?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteList() }
                    .disabled(activeOperation != nil)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(deleteConfirmMessage)
            }
            .alert(
                operationFailure?.operation.errorTitle ?? "Couldn’t Complete Action",
                isPresented: isShowingOperationFailure,
                presenting: operationFailure
            ) { _ in
                Button("OK", role: .cancel) { operationFailure = nil }
                    .accessibilityIdentifier("listedit.persistence.error.dismiss")
            } message: { failure in
                Text(failure.message)
            }
            // Full-screen because parent-list picking is a navigation task.
            .fullScreenCover(isPresented: $showingParentPicker) {
                ParentPickerSheet(
                    store: store,
                    movingListId: existing?.id,
                    initialSelection: parentId
                ) { picked in
                    parentId = picked
                }
            }
            .onAppear {
                if existing == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        nameFocused = true
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                // Inline emoji-keyboard bridge. Permanent in the hierarchy
                // (NOT in a sheet) so the keyboard pops up directly over
                // the New List sheet — no extra UI required.
                EmojiInputField(text: $emojiInput, isFocused: $emojiFieldFocused)
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                if emojiFieldFocused {
                    Button {
                        emojiFieldFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .accessibilityLabel("Hide keyboard")
                }
            }
            .animation(.snappy(duration: 0.2), value: emojiFieldFocused)
            .onChange(of: emojiInput) { _, new in
                guard !new.isEmpty else { return }
                let candidate = String(new.prefix(1))
                if candidate.unicodeScalars.contains(where: {
                    $0.properties.isEmojiPresentation || $0.properties.isEmoji
                }) {
                    icon = candidate
                }
                emojiInput = ""
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(activeOperation != nil || deleteNeedsRetry)
    }

    // MARK: - Cards

    private var iconAndNameCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(ListsTokens.listColor(color))
                    .frame(width: 84, height: 84)
                ListIconGlyph(
                    icon: icon,
                    size: 38,
                    weight: .semibold,
                    color: .white
                )
            }
            .padding(.top, 4)

            TextField("List Name", text: $name)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var parentRowCard: some View {
        Button {
            showingParentPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.gray)
                    )

                Text("Sublist")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                Text(parentDisplayName)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .allowsTightening(true)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var parentDisplayName: String {
        guard let id = parentId,
              let parent = store.lists.first(where: { $0.id == id })
        else { return "None" }
        return parent.name
    }

    private var listTypeCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    listTypeLeadingLabel
                    listTypeMenu
                        .padding(.leading, 42)
                }
            } else {
                HStack(spacing: 12) {
                    listTypeLeadingLabel
                    Spacer(minLength: 8)
                    listTypeMenu
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var listTypeLeadingLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: listType.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.blue)
                )

            Text("List Type")
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .allowsTightening(true)
                .layoutPriority(1)
        }
    }

    private var listTypeMenu: some View {
        Menu {
            Picker("", selection: $listType) {
                Label("Standard", systemImage: "list.bullet").tag(ListEditType.standard)
                Label("Shopping", systemImage: "cart.fill").tag(ListEditType.shopping)
            }
        } label: {
            HStack(spacing: 4) {
                Text(listType.displayName)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .allowsTightening(true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                   alignment: .leading)
        }
    }

    private var colorGridCard: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(ListsTokens.listColorPalette, id: \.self) { c in
                Button {
                    color = c
                } label: {
                    ZStack {
                        Circle()
                            .fill(ListsTokens.listColor(c))
                            .frame(width: 38, height: 38)
                        if color == c {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                                .frame(width: 50, height: 50)
                        }
                    }
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(c.rawValue.capitalized))
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var iconGridCard: some View {
        let cells: [IconCell] = [.emoji] + Self.iconChoices.map { .symbol($0) }
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(cells, id: \.self) { cell in
                iconCell(cell)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private enum IconCell: Hashable {
        case emoji
        case symbol(String)
    }

    @ViewBuilder
    private func iconCell(_ cell: IconCell) -> some View {
        switch cell {
        case .emoji:
            let isSelected = !ListIconGlyph.isSFSymbol(icon)
            Button {
                nameFocused = false
                emojiFieldFocused = true
            } label: {
                ZStack {
                    // Two-tone: full circle in muted blue, with the smile
                    // glyph drawn in bright blue. The glyph's eye/mouth
                    // cutouts reveal the darker blue underneath. This
                    // appearance never changes — picking an emoji updates
                    // the big preview, not the button.
                    Circle()
                        .fill(Color.blue.opacity(0.30))
                        .frame(width: 38, height: 38)
                    Image(systemName: "face.smiling.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.blue)

                    if isSelected {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                            .frame(width: 50, height: 50)
                    }
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pick emoji")

        case .symbol(let sym):
            let isSelected = (icon == sym)
            Button {
                icon = sym
            } label: {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color(.tertiarySystemFill))
                        .frame(width: 38, height: 38)
                    Image(systemName: sym)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                            .frame(width: 50, height: 50)
                    }
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(sym))
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            Text("Delete List")
                .font(.body)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.top, 8)
    }

    // MARK: - Derived

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draft: ListEditDraft {
        ListEditDraft(
            name: name,
            icon: icon,
            color: color,
            listType: listType,
            parentId: parentId
        )
    }

    private var itemCountInList: Int {
        store.items.filter { item in
            item.deletedAt == nil && listCascadeIds.contains(item.listId)
        }.count
    }

    private var listCascadeIds: Set<String> {
        guard let id = existing?.id else { return [] }
        return Set([id] + store.descendantIds(of: id))
    }

    // MARK: - Actions

    private func save() {
        guard activeOperation == nil, !deleteNeedsRetry else { return }
        let now = Date()
        let nextPosition = nextSiblingPosition(under: parentId)
        let updated = draft.makeList(existing: existing, now: now, nextPosition: nextPosition)
        let operation: Operation = existing == nil ? .adding : .saving
        activeOperation = operation
        Task {
            defer { activeOperation = nil }
            do {
                if existing == nil {
                    try await store.addList(updated)
                } else {
                    try await store.updateList(updated)
                }
                dismiss()
            } catch {
                operationFailure = OperationFailure(
                    operation: operation,
                    message: error.localizedDescription
                )
            }
        }
    }

    private var isShowingOperationFailure: Binding<Bool> {
        Binding(
            get: { operationFailure != nil },
            set: { isPresented in
                if !isPresented {
                    operationFailure = nil
                }
            }
        )
    }

    /// Next free `position` value among siblings under `parent`. Keeps
    /// new lists below existing peers and avoids cross-group renumbering.
    private func nextSiblingPosition(under parent: String?) -> Double {
        let siblings = store.lists.filter { $0.parentId == parent && $0.deletedAt == nil }
        return (siblings.map(\.position).max() ?? 0) + 1
    }

    private var deleteConfirmMessage: String {
        let descCount = existing.map { store.descendantIds(of: $0.id).count } ?? 0
        let itemNoun = itemCountInList == 1 ? "item" : "items"
        let itemPart = "\"\(name)\" and \(itemCountInList) \(itemNoun) will move to Recently Deleted."
        if descCount > 0 {
            let listNoun = descCount == 1 ? "sub-list" : "sub-lists"
            return itemPart + " This will also move \(descCount) \(listNoun) to Recently Deleted."
        }
        return itemPart
    }

    private func deleteList() {
        guard let existing, activeOperation == nil else { return }
        let operation = Operation.deleting
        activeOperation = operation
        Task {
            defer { activeOperation = nil }
            do {
                try await store.softDeleteList(existing.id)
                deleteNeedsRetry = false
                dismiss()
            } catch {
                // A cascade may have committed a prefix. Retrying Delete is
                // safe; saving this old draft would instead resurrect only
                // the root list and split the subtree.
                deleteNeedsRetry = true
                operationFailure = OperationFailure(
                    operation: operation,
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Icon palette

    /// Minimal v1 palette. Emoji cell is prepended in `iconGridCard`.
    private static let iconChoices: [String] = [
        "list.bullet",
        "checklist",
        "calendar.badge.checkmark",
        "cart.fill"
    ]
}
