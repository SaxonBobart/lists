import SwiftUI

/// Overflow menu for a user list. Owns menu layout and preference bindings;
/// `ListDetailView` supplies the screen-routing actions.
struct ListDetailToolbarMenu: View {
    let listId: String
    let hasSections: Bool
    let prefs: ListViewPreferences
    let onNewSection: () -> Void
    let onEditSections: () -> Void
    let onNewSublist: () -> Void
    let onSelectItems: () -> Void
    let onEditList: () -> Void
    let onDeleteList: () -> Void

    var body: some View {
        Menu {
            manageSectionsMenu
            sortMenuSection
            showCompletedButton
            showPastEventsButton
            Divider()
            Button(action: onNewSublist) {
                Label("New Sublist", systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier("list.menu.newSublist")
            Button(action: onSelectItems) {
                Label("Select Items", systemImage: "checkmark.circle")
            }
            .accessibilityIdentifier("list.menu.selectMode")
            Button(action: onEditList) {
                Label("Edit List", systemImage: "info.circle")
            }
            .accessibilityIdentifier("list.menu.edit")
            Button(role: .destructive, action: onDeleteList) {
                Label("Delete List", systemImage: "trash")
            }
            .tint(.red)
            .accessibilityIdentifier("list.menu.delete")
        } label: {
            Label("List Options", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .accessibilityIdentifier("list.menu")
    }

    private var manageSectionsMenu: some View {
        Menu {
            Button(action: onNewSection) {
                Label("New Section", systemImage: "plus")
            }
            .accessibilityIdentifier("list.menu.newSection")
            Button(action: onEditSections) {
                Label("Edit Sections", systemImage: "pencil")
            }
            .disabled(!hasSections)
            .accessibilityIdentifier("list.menu.editSections")
        } label: {
            Label("Manage Sections", systemImage: "list.bullet.below.rectangle")
        }
    }

    @ViewBuilder
    private var sortMenuSection: some View {
        let currentMode = prefs.sort(for: listId)
        Menu {
            Picker(selection: sortBinding) {
                ForEach(ListViewPreferences.SortMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)

            if currentMode != .manual {
                Picker(selection: sortDirectionBinding) {
                    ForEach(ListViewPreferences.SortDirection.allCases, id: \.self) { direction in
                        Text(currentMode.directionLabel(direction)).tag(direction)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label {
                Text("Sort By")
                Text(currentMode.label)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("list.menu.sort")
        }
    }

    private var showCompletedButton: some View {
        Button {
            showCompletedBinding.wrappedValue.toggle()
        } label: {
            Label(
                showCompletedBinding.wrappedValue ? "Hide Completed Items" : "Show Completed Items",
                systemImage: showCompletedBinding.wrappedValue ? "eye.slash" : "eye"
            )
        }
        .accessibilityIdentifier("list.menu.showCompleted")
    }

    private var showPastEventsButton: some View {
        Button {
            showPastEventsBinding.wrappedValue.toggle()
        } label: {
            Label(
                showPastEventsBinding.wrappedValue ? "Hide Past Events" : "Show Past Events",
                systemImage: showPastEventsBinding.wrappedValue ? "calendar.badge.minus" : "calendar.badge.clock"
            )
        }
        .accessibilityIdentifier("list.menu.showPastEvents")
    }

    private var sortBinding: Binding<ListViewPreferences.SortMode> {
        Binding(
            get: { prefs.sort(for: listId) },
            set: { prefs.setSort($0, for: listId) }
        )
    }

    private var sortDirectionBinding: Binding<ListViewPreferences.SortDirection> {
        Binding(
            get: { prefs.sortDirection(for: listId) },
            set: { prefs.setSortDirection($0, for: listId) }
        )
    }

    private var showCompletedBinding: Binding<Bool> {
        Binding(
            get: { prefs.showCompleted(for: listId) },
            set: { prefs.setShowCompleted($0, for: listId) }
        )
    }

    private var showPastEventsBinding: Binding<Bool> {
        Binding(
            get: { prefs.showPastEvents(for: listId) },
            set: { prefs.setShowPastEvents($0, for: listId) }
        )
    }
}
