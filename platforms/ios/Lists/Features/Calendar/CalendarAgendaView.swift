import SwiftUI

struct CalendarAgendaView: View {
    let days: [Date]
    let index: CalendarEntryIndex
    var calendar: Calendar = .current
    let colorForEntry: (CalendarEntry) -> Color
    let canToggle: (CalendarEntry) -> Bool
    let onToggle: (CalendarEntry) -> Void
    let onOpen: (CalendarEntry) -> Void
    var onDuplicate: (CalendarEntry) -> Void = { _ in }
    var showsEmptyDays = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(visibleDays, id: \.self) { day in
                    CalendarAgendaDaySection(
                        day: day,
                        entries: index.entries(on: day),
                        calendar: calendar,
                        colorForEntry: colorForEntry,
                        canToggle: canToggle,
                        onToggle: onToggle,
                        onOpen: onOpen,
                        onDuplicate: onDuplicate
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .overlay {
            if visibleDays.isEmpty {
                ContentUnavailableView(
                    "Nothing scheduled",
                    systemImage: "calendar",
                    description: Text("Dated items in this range will appear here.")
                )
            }
        }
    }

    private var visibleDays: [Date] {
        if showsEmptyDays { return days }
        return days.filter { !index.entries(on: $0).isEmpty }
    }
}

struct CalendarAgendaDaySection: View {
    let day: Date
    let entries: [CalendarEntry]
    var calendar: Calendar = .current
    let colorForEntry: (CalendarEntry) -> Color
    let canToggle: (CalendarEntry) -> Bool
    let onToggle: (CalendarEntry) -> Void
    let onOpen: (CalendarEntry) -> Void
    var onDuplicate: (CalendarEntry) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(day.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 4)

            if entries.isEmpty {
                Text("No items")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 10)
            } else {
                ForEach(entries) { entry in
                    CalendarAgendaEntryRow(
                        entry: entry,
                        color: colorForEntry(entry),
                        canToggle: canToggle(entry),
                        onToggle: { onToggle(entry) },
                        onOpen: { onOpen(entry) },
                        onDuplicate: { onDuplicate(entry) },
                        instanceIdentifier: entryIdentifier(entry)
                    )
                    if entry.id != entries.last?.id {
                        Divider()
                            .padding(.leading, entry.isCompletable ? 36 : 16)
                    }
                }
            }
        }
    }

    private func entryIdentifier(_ entry: CalendarEntry) -> String {
        let dayId = CalendarDateMath.dayIdentifier(day, calendar: calendar)
        return "calendar.agenda.entry.\(entry.itemId.uuidString).\(entry.id.source.rawValue).\(dayId)"
    }
}
