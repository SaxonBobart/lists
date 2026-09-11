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
    var actionsForEntry: ((CalendarEntry) -> ItemActions?)? = nil
    var dragPayload: (CalendarEntry) -> String? = { _ in nil }
    var showsEmptyDays = false
    var scrollTarget: Date?
    var scrollRequestID = 0
    var onExpandPast: () -> Void = {}
    var onExpandFuture: () -> Void = {}

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Color.clear
                        .frame(height: 1)
                        .id("calendar.agenda.past")
                        .onAppear(perform: onExpandPast)

                    ForEach(visibleDays, id: \.self) { day in
                        daySlot(day)
                            .id(dayID(day))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("calendar.agenda.future")
                        .onAppear(perform: onExpandFuture)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 104)
            }
            .onAppear { scroll(to: scrollTarget, using: proxy, animated: false) }
            .onChange(of: scrollRequestID) {
                scroll(to: scrollTarget, using: proxy, animated: true)
            }
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

    @ViewBuilder
    private func daySlot(_ day: Date) -> some View {
        let entries = index.entries(on: day)
        if showsEmptyDays || !entries.isEmpty {
            CalendarAgendaDaySection(
                day: day,
                entries: entries,
                calendar: calendar,
                colorForEntry: colorForEntry,
                canToggle: canToggle,
                onToggle: onToggle,
                onOpen: onOpen,
                onDuplicate: onDuplicate,
                actionsForEntry: actionsForEntry,
                dragPayload: dragPayload
            )
        }
    }

    private func scroll(to target: Date?, using proxy: ScrollViewProxy, animated: Bool) {
        guard let target else { return }
        guard let normalized = CalendarDateMath.agendaScrollDay(
            target: target, availableDays: visibleDays, calendar: calendar
        ) else { return }
        if animated {
            withAnimation(.smooth) {
                proxy.scrollTo(dayID(normalized), anchor: .top)
            }
        } else {
            proxy.scrollTo(dayID(normalized), anchor: .top)
        }
    }

    private func dayID(_ day: Date) -> String {
        "calendar.agenda.day.\(CalendarDateMath.dayIdentifier(day, calendar: calendar))"
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
    var actionsForEntry: ((CalendarEntry) -> ItemActions?)? = nil
    var dragPayload: (CalendarEntry) -> String? = { _ in nil }

    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsHeader {
                HStack(alignment: .firstTextBaseline) {
                    Text(day.formatted(.dateTime.weekday(.wide)))
                        .font(.headline)
                    Text(day.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.bottom, 4)
            }

            if entries.isEmpty {
                Text("No items")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 10)
            } else {
                ForEach(entries) { entry in
                    VStack(spacing: 0) {
                        agendaRow(entry)
                        if entry.id != entries.last?.id {
                            Divider()
                                .padding(.leading, entry.isCompletable ? 52 : 16)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func agendaRow(_ entry: CalendarEntry) -> some View {
        let row = CalendarAgendaEntryRow(
            entry: entry,
            color: colorForEntry(entry),
            canToggle: canToggle(entry),
            onToggle: { onToggle(entry) },
            onOpen: { onOpen(entry) },
            onDuplicate: { onDuplicate(entry) },
            actions: actionsForEntry?(entry),
            instanceIdentifier: entryIdentifier(entry)
        )
        if let payload = dragPayload(entry) {
            row.draggable(payload)
        } else {
            row
        }
    }

    private func entryIdentifier(_ entry: CalendarEntry) -> String {
        let dayId = CalendarDateMath.dayIdentifier(day, calendar: calendar)
        return "calendar.agenda.entry.\(entry.itemId.uuidString).\(entry.id.source.rawValue).\(dayId)"
    }
}
