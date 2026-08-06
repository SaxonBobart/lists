import SwiftUI

enum CalendarTimelinePolicy {
    static func initialHour(
        for day: Date,
        entries: [CalendarEntry],
        now: Date,
        calendar: Calendar
    ) -> Int {
        if calendar.isDate(day, inSameDayAs: now) {
            return max(0, calendar.component(.hour, from: now) - 2)
        }
        if let firstTimed = entries.filter({ !$0.isAllDay }).min(by: { $0.start < $1.start }) {
            return max(0, calendar.component(.hour, from: firstTimed.start) - 2)
        }
        return 7
    }

    static func canResize(_ entry: CalendarEntry) -> Bool {
        entry.isEditableOccurrence && entry.type == .event
    }
}

struct CalendarTimelineView: View {
    private struct Placement: Identifiable {
        let entry: CalendarEntry
        let column: Int
        let columnCount: Int

        var id: CalendarEntry.ID { entry.id }
    }

    let days: [Date]
    @Binding var selectedDate: Date
    let index: CalendarEntryIndex
    let calendar: Calendar
    let tint: Color
    let colorForEntry: (CalendarEntry) -> Color
    let onOpen: (CalendarEntry) -> Void
    let onReschedule: (CalendarEntry, Date, Date) -> Void
    let onDuplicate: (CalendarEntry) -> Void
    let onCreateAt: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var creationPoint: CGPoint?

    private let hourHeight: CGFloat = 64
    private let timeGutterWidth: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            dayStrip
            allDayLane
            Divider()
            timeline
        }
        .background(Color(.systemBackground))
        .onChange(of: days, initial: true) {
            guard let first = days.first,
                  !days.contains(where: { calendar.isDate($0, inSameDayAs: selectedDate) }) else {
                return
            }
            selectedDate = first
        }
    }

    private var dayStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    dayButton(day)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .background(.bar)
        .accessibilityLabel("Days in range")
        .accessibilityIdentifier("calendar.timeline.days")
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: focusedDay)
        let isToday = calendar.isDateInToday(day)
        return Button {
            withAnimation(reduceMotion ? nil : .smooth) {
                selectedDate = day
            }
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                Text(day.formatted(.dateTime.day()))
                    .font(.headline.weight(isToday || isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? .white : (isToday ? tint : .primary))
            .frame(minWidth: 44, minHeight: 46)
            .padding(.horizontal, 4)
            .background(isSelected ? tint : Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(
            "calendar.timeline.day.\(CalendarDateMath.dayIdentifier(day, calendar: calendar))"
        )
    }

    @ViewBuilder
    private var allDayLane: some View {
        if !allDayEntries.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text("All day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: timeGutterWidth - 4, alignment: .trailing)
                    .padding(.top, 5)

                VStack(spacing: 4) {
                    ForEach(allDayEntries.prefix(3)) { entry in
                        CalendarEntryChip(
                            entry: entry,
                            color: colorForEntry(entry),
                            compact: false,
                            onOpen: { onOpen(entry) },
                            onDuplicate: { onDuplicate(entry) },
                            instanceIdentifier: timelineEntryIdentifier(entry, day: focusedDay)
                        )
                    }
                    if allDayEntries.count > 3 {
                        Text("+\(allDayEntries.count - 3) more")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground).opacity(0.55))
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    timeGutter
                    dayColumn(focusedDay)
                }
                .frame(height: hourHeight * 24)
                .padding(.bottom, 100)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onAppear { scrollToInitialHour(using: proxy, animated: false) }
            .onChange(of: focusedDay) {
                scrollToInitialHour(using: proxy, animated: true)
            }
        }
    }

    private var timeGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(
                        width: timeGutterWidth,
                        height: hourHeight,
                        alignment: .topTrailing
                    )
                    .offset(y: -7)
                    .padding(.trailing, 7)
                    .id("calendar.hour.\(hour)")
            }
        }
        .frame(width: timeGutterWidth, height: hourHeight * 24, alignment: .topTrailing)
        .accessibilityHidden(true)
    }

    private func dayColumn(_ day: Date) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                hourGrid

                ForEach(placements(on: day)) { placement in
                    timedBlock(placement, day: day, width: geometry.size.width)
                }

                if calendar.isDateInToday(day) {
                    currentTimeLine
                }
            }
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { creationPoint = $0.location }
            )
            .onLongPressGesture(minimumDuration: 0.45) {
                let point = creationPoint ?? CGPoint(x: 0, y: hourHeight * 9)
                creationPoint = nil
                onCreateAt(date(on: day, y: point.y))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("calendar.timeline.grid")
    }

    private var hourGrid: some View {
        ZStack(alignment: .top) {
            ForEach(0...24, id: \.self) { hour in
                Rectangle()
                    .fill(Color.secondary.opacity(hour == 0 ? 0.25 : 0.13))
                    .frame(height: 0.5)
                    .offset(y: CGFloat(hour) * hourHeight)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func timedBlock(
        _ placement: Placement,
        day: Date,
        width: CGFloat
    ) -> some View {
        let entry = placement.entry
        let startMinute = clippedMinute(entry.start, on: day)
        let endMinute = max(startMinute + 20, clippedMinute(entry.end, on: day, isEnd: true))
        let y = CGFloat(startMinute) / 60 * hourHeight
        let height = max(28, CGFloat(endMinute - startMinute) / 60 * hourHeight)
        let spacing: CGFloat = 3
        let available = max(1, width - spacing * CGFloat(placement.columnCount + 1))
        let blockWidth = available / CGFloat(placement.columnCount)
        let x = spacing + CGFloat(placement.column) * (blockWidth + spacing)

        return CalendarTimelineEntryBlock(
            entry: entry,
            color: colorForEntry(entry),
            height: height,
            canResize: CalendarTimelinePolicy.canResize(entry),
            onOpen: { onOpen(entry) },
            onDuplicate: { onDuplicate(entry) },
            onMove: { minuteDelta in
                move(entry, by: minuteDelta)
            },
            onResize: { minuteDelta in
                resize(entry, by: minuteDelta)
            }
        )
        .frame(width: blockWidth, height: height)
        .offset(x: x, y: y)
        .accessibilityIdentifier(timelineEntryIdentifier(entry, day: day))
    }

    private var currentTimeLine: some View {
        let now = Date.now
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
        }
        .offset(x: -3, y: CGFloat(minute) / 60 * hourHeight)
        .accessibilityHidden(true)
    }

    private var focusedDay: Date {
        days.first(where: { calendar.isDate($0, inSameDayAs: selectedDate) })
            ?? days.first
            ?? calendar.startOfDay(for: selectedDate)
    }

    private var focusedEntries: [CalendarEntry] {
        index.entries(on: focusedDay)
    }

    private var allDayEntries: [CalendarEntry] {
        focusedEntries.filter(\.isAllDay)
    }

    private func scrollToInitialHour(using proxy: ScrollViewProxy, animated: Bool) {
        let hour = CalendarTimelinePolicy.initialHour(
            for: focusedDay,
            entries: focusedEntries,
            now: .now,
            calendar: calendar
        )
        if animated && !reduceMotion {
            withAnimation(.smooth) {
                proxy.scrollTo("calendar.hour.\(hour)", anchor: .top)
            }
        } else {
            proxy.scrollTo("calendar.hour.\(hour)", anchor: .top)
        }
    }

    private func move(_ entry: CalendarEntry, by minuteDelta: Int) {
        guard entry.isEditableOccurrence, minuteDelta != 0 else { return }
        let newStart = calendar.date(byAdding: .minute, value: minuteDelta, to: entry.start)
            ?? entry.start
        let newEnd = calendar.date(byAdding: .minute, value: minuteDelta, to: entry.end)
            ?? entry.end
        onReschedule(entry, newStart, newEnd)
    }

    private func resize(_ entry: CalendarEntry, by minuteDelta: Int) {
        guard CalendarTimelinePolicy.canResize(entry), minuteDelta != 0 else { return }
        let candidate = calendar.date(byAdding: .minute, value: minuteDelta, to: entry.end)
            ?? entry.end
        let minimum = calendar.date(byAdding: .minute, value: 15, to: entry.start)
            ?? entry.end
        onReschedule(entry, entry.start, max(candidate, minimum))
    }

    private func placements(on day: Date) -> [Placement] {
        let entries = index.entries(on: day)
            .filter { !$0.isAllDay }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.end < $1.end
            }
        guard !entries.isEmpty else { return [] }

        var clusters: [[CalendarEntry]] = []
        var cluster: [CalendarEntry] = []
        var clusterEnd = Date.distantPast
        for entry in entries {
            if cluster.isEmpty || entry.start < clusterEnd {
                cluster.append(entry)
                clusterEnd = max(clusterEnd, entry.end)
            } else {
                clusters.append(cluster)
                cluster = [entry]
                clusterEnd = entry.end
            }
        }
        if !cluster.isEmpty { clusters.append(cluster) }

        return clusters.flatMap { cluster in
            var columnEnds: [Date] = []
            var assignments: [(CalendarEntry, Int)] = []
            for entry in cluster {
                let available = columnEnds.firstIndex(where: { $0 <= entry.start })
                let column = available ?? columnEnds.count
                if let available {
                    columnEnds[available] = entry.end
                } else {
                    columnEnds.append(entry.end)
                }
                assignments.append((entry, column))
            }
            return assignments.map {
                Placement(entry: $0.0, column: $0.1, columnCount: max(1, columnEnds.count))
            }
        }
    }

    private func clippedMinute(_ date: Date, on day: Date, isEnd: Bool = false) -> Int {
        let start = calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        if date <= start { return 0 }
        if date >= next { return 24 * 60 }
        let components = calendar.dateComponents([.minute], from: start, to: date)
        let value = components.minute ?? (isEnd ? 24 * 60 : 0)
        return min(24 * 60, max(0, value))
    }

    private func date(on day: Date, y: CGFloat) -> Date {
        let rawMinutes = Int(max(0, min(hourHeight * 24, y)) / hourHeight * 60)
        let rounded = min(23 * 60 + 45, max(0, Int(round(Double(rawMinutes) / 15)) * 15))
        return calendar.date(
            byAdding: .minute,
            value: rounded,
            to: calendar.startOfDay(for: day)
        ) ?? day
    }

    private func hourLabel(_ hour: Int) -> String {
        guard let date = calendar.date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: hour)
        ) else {
            return "\(hour)"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func timelineEntryIdentifier(_ entry: CalendarEntry, day: Date) -> String {
        let dayId = CalendarDateMath.dayIdentifier(day, calendar: calendar)
        return "calendar.timeline.entry.\(entry.itemId.uuidString).\(entry.id.source.rawValue).\(dayId)"
    }
}

private struct CalendarTimelineEntryBlock: View {
    let entry: CalendarEntry
    let color: Color
    let height: CGFloat
    let canResize: Bool
    let onOpen: () -> Void
    let onDuplicate: () -> Void
    let onMove: (Int) -> Void
    let onResize: (Int) -> Void

    private let hourHeight: CGFloat = 64

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(height < 44 ? 1 : 2)
                if height >= 44 {
                    Text(entry.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .opacity(0.76)
                }
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                color.opacity(entry.status == .completed ? 0.10 : 0.18),
                in: .rect(cornerRadius: 7)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }
            .opacity(entry.status == .completed ? 0.62 : (entry.isProjected ? 0.72 : 1))
        }
        .buttonStyle(.plain)
        .gesture(moveGesture)
        .overlay(alignment: .bottom) {
            if canResize {
                Capsule()
                    .fill(color.opacity(0.72))
                    .frame(width: 24, height: 3)
                    .padding(.bottom, 2)
                    .contentShape(.rect.inset(by: -8))
                    .gesture(resizeGesture)
                    .accessibilityHidden(true)
            }
        }
        .contextMenu {
            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(entry.isEditableOccurrence ? "Drag vertically to reschedule" : "")
        .accessibilityActions {
            if entry.isEditableOccurrence {
                Button("Move 15 minutes earlier") { onMove(-15) }
                Button("Move 15 minutes later") { onMove(15) }
            }
            if canResize {
                Button("Shorten by 15 minutes") { onResize(-15) }
                Button("Extend by 15 minutes") { onResize(15) }
            }
            Button("Duplicate", action: onDuplicate)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard entry.isEditableOccurrence else { return }
                onMove(minuteDelta(for: value.translation.height))
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onEnded { value in
                onResize(minuteDelta(for: value.translation.height))
            }
    }

    private var accessibilityLabel: String {
        "\(entry.title), \(entry.start.formatted(date: .omitted, time: .shortened)) to \(entry.end.formatted(date: .omitted, time: .shortened))"
    }

    private func minuteDelta(for translation: CGFloat) -> Int {
        Int((translation / hourHeight * 60) / 15) * 15
    }
}
