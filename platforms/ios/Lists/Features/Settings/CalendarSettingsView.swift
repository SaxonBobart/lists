import SwiftUI

struct CalendarSettingsView: View {
    let store: ItemStore
    @Bindable var preferences: CalendarPreferences

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(
                    icon: "checkmark.circle",
                    label: "Tasks",
                    isOn: $preferences.showTasks
                )
                .accessibilityIdentifier("settings.calendar.tasks")
                SettingsToggleRow(
                    icon: "calendar",
                    label: "Events",
                    isOn: $preferences.showEvents
                )
                .accessibilityIdentifier("settings.calendar.events")
                SettingsToggleRow(
                    icon: "repeat",
                    label: "Habits",
                    isOn: $preferences.showHabits
                )
                .accessibilityIdentifier("settings.calendar.habits")
                SettingsToggleRow(
                    icon: "text.document",
                    label: "Notes",
                    isOn: $preferences.showNotes
                )
                .accessibilityIdentifier("settings.calendar.notes")
            } header: {
                Text("Item Types")
            } footer: {
                Text("Only dated documents appear. Turning a type off hides it from calendar views without changing the document.")
            }

            Section {
                Picker(selection: $preferences.recurrenceVisibility) {
                    ForEach(CalendarPreferences.RecurrenceVisibility.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                } label: {
                    SettingsRowLabel(title: "Show", icon: "repeat")
                }
                .pickerStyle(.menu)
                .tint(ListsTokens.Foreground.secondary)
                .accessibilityIdentifier("settings.calendar.recurrence")

                SettingsToggleRow(
                    icon: "checkmark.circle",
                    label: "Completed History",
                    isOn: $preferences.showCompletedHistory
                )
                .accessibilityIdentifier("settings.calendar.completedHistory")
                SettingsToggleRow(
                    icon: "xmark.circle",
                    label: "Missed History",
                    isOn: $preferences.showMissedHistory
                )
                .accessibilityIdentifier("settings.calendar.missedHistory")
            } header: {
                Text("Repeating Items")
            } footer: {
                Text("History is off by default because recurring documents already have a dedicated completion-history screen.")
            }

            Section {
                SettingsToggleRow(
                    icon: "checkmark",
                    label: "Completed Items",
                    isOn: $preferences.showCompletedItems
                )
                .accessibilityIdentifier("settings.calendar.completedItems")
                SettingsToggleRow(
                    icon: "calendar.badge.plus",
                    label: "Weekends",
                    isOn: $preferences.showWeekends
                )
                .accessibilityIdentifier("settings.calendar.weekends")
                SettingsToggleRow(
                    icon: "number",
                    label: "Week Numbers",
                    isOn: $preferences.showWeekNumbers
                )
                .accessibilityIdentifier("settings.calendar.weekNumbers")
            } header: {
                Text("Display")
            }

            Section {
                ForEach(activeLists, id: \.id) { list in
                    Toggle(isOn: visibleBinding(for: list.id)) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(ListsTokens.listColor(list.color))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(list.name)
                                .foregroundStyle(.primary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .accessibilityIdentifier("settings.calendar.list.\(list.id)")
                }
            } header: {
                Text("Lists")
            } footer: {
                Text("These filters affect the global calendar. A calendar opened from a list still shows that list.")
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var activeLists: [ItemList] {
        store.lists
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private func visibleBinding(for listId: String) -> Binding<Bool> {
        Binding(
            get: { !preferences.hiddenListIds.contains(listId) },
            set: { preferences.setListHidden(listId, !$0) }
        )
    }
}
