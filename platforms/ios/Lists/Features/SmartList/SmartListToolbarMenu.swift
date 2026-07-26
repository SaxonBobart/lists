import SwiftUI

struct SmartListToolbarMenu: View {
    let smartList: SmartList
    let prefs: ListViewPreferences

    private var prefsKey: String { "smart:\(smartList.rawValue)" }
    private var defaultViewMode: ListViewPreferences.ViewMode {
        smartList == .calendar ? .calendar : .list
    }
    private var currentViewMode: ListViewPreferences.ViewMode {
        let requested = prefs.viewMode(for: prefsKey, default: defaultViewMode)
        return requested == .columns ? .list : requested
    }

    var body: some View {
        Menu {
            viewMenu
            Divider()
            if smartList != .scheduled {
                sortMenu
            }
            if smartList != .completed {
                showCompletedButton
            }
            if smartList != .completed {
                showPastEventsButton
            }
            if smartList == .scheduled {
                showOverdueToggle
            }
        } label: {
            Label("View Options", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .accessibilityIdentifier("smartlist.\(smartList.rawValue).menu")
    }

    private var viewMenu: some View {
        let current = currentViewMode
        return Menu {
            Picker(selection: viewModeBinding) {
                ForEach(ListViewPreferences.ViewMode.queryModes, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.systemImage)
                        .tag(mode)
                        .accessibilityIdentifier(
                            "smartlist.\(smartList.rawValue).menu.view.\(mode.rawValue)"
                        )
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("View As")
                Text(current.label)
            } icon: {
                Image(systemName: current.systemImage)
            }
            .accessibilityIdentifier("smartlist.\(smartList.rawValue).menu.view")
        }
    }

    private var sortMenu: some View {
        let currentMode = prefs.sort(for: prefsKey)
        return Menu {
            Picker(selection: sortBinding) {
                ForEach(ListViewPreferences.SortMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.systemImage)
                        .tag(mode)
                        .accessibilityIdentifier("smartlist.\(smartList.rawValue).menu.sort.\(mode.rawValue)")
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
            .accessibilityIdentifier("smartlist.\(smartList.rawValue).menu.sort")
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
        .accessibilityIdentifier("smartlist.\(smartList.rawValue).menu.showCompleted")
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
        .accessibilityIdentifier("smartlist.\(smartList.rawValue).menu.showPastEvents")
    }

    private var showOverdueToggle: some View {
        Toggle(isOn: showOverdueBinding) {
            Label("Show Overdue", systemImage: "exclamationmark.triangle")
        }
        .accessibilityIdentifier("smartlist.\(smartList.rawValue).menu.showOverdue")
    }

    private var sortBinding: Binding<ListViewPreferences.SortMode> {
        Binding(
            get: { prefs.sort(for: prefsKey) },
            set: { prefs.setSort($0, for: prefsKey) }
        )
    }

    private var viewModeBinding: Binding<ListViewPreferences.ViewMode> {
        Binding(
            get: { currentViewMode },
            set: { prefs.setViewMode($0, for: prefsKey) }
        )
    }

    private var sortDirectionBinding: Binding<ListViewPreferences.SortDirection> {
        Binding(
            get: { prefs.sortDirection(for: prefsKey) },
            set: { prefs.setSortDirection($0, for: prefsKey) }
        )
    }

    private var showPastEventsBinding: Binding<Bool> {
        Binding(
            get: { prefs.showPastEvents(for: prefsKey) },
            set: { prefs.setShowPastEvents($0, for: prefsKey) }
        )
    }

    private var showCompletedBinding: Binding<Bool> {
        Binding(
            get: { prefs.showCompleted(for: prefsKey) },
            set: { prefs.setShowCompleted($0, for: prefsKey) }
        )
    }

    private var showOverdueBinding: Binding<Bool> {
        Binding(
            get: { prefs.showOverdue(for: prefsKey) },
            set: { prefs.setShowOverdue($0, for: prefsKey) }
        )
    }
}
