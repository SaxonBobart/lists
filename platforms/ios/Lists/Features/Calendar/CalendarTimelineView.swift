import SwiftUI

struct CalendarTimelineView: View {
    private struct Placement: Identifiable {
        let entry: CalendarEntry
        let column: Int
        let columnCount: Int

        var id: CalendarEntry.ID { entry.id }
    }

    let days: [Date]
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
    private let timeGutterWidth: CGFloat = 46

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            allDayLane
            Divider()
            timeline
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: timeGutterWidth, height: 42)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.headline.weight(calendar.isDateInToday(day) ? .bold : .medium))
                        .foregroundStyle(calendar.isDateInToday(day) ? .white : .primary)
                        .frame(width: 30, height: 30)
                        .background {
                            if calendar.isDateInToday(day) {
                                Circle().fill(tint)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            }
        }
        .padding(.vertical, 6)
        .background(.background)
    }

    @ViewBuilder
    private var allDayLane: some View {
        let hasAllDay = days.contains { day in
            index.entries(on: day).contains(where: \.isAllDay)
        }
        if hasAllDay {
            HStack(alignment: .top, spacing: 0) {
                Text("all-day")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: timeGutterWidth, alignment: .trailing)
                    .padding(.trailing, 5)
                    .padding(.top, 4)

                ForEach(days, id: \.self) { day in
                    VStack(spacing: 3) {
                        ForEach(index.entries(on: day).filter(\.isAllDay).prefix(3)) { entry in
                            CalendarEntryChip(
                                entry: entry,
                                color: colorForEntry(entry),
                                compact: false,
                                onOpen: { onOpen(entry) },
                                onDuplicate: { onDuplicate(entry) },
                                instanceIdentifier: timelineEntryIdentifier(entry, day: day)
                            )
                        }
                        let overflow = index.entries(on: day).filter(\.isAllDay).count - 3
                        if overflow > 0 {
                            Text("+\(overflow)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 2)
                }
            }
            .padding(.vertical, 5)
            .background(Color(.secondarySystemBackground).opacity(0.55))
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    timeGutter
                    ForEach(days, id: \.self) { day in
                        dayColumn(day)
                    }
                }
                .frame(height: hourHeight * 24)
                .padding(.bottom, 100)
            }
            .onAppear {
                let hour = max(0, calendar.component(.hour, from: .now) - 1)
                proxy.scrollTo("calendar.hour.\(hour)", anchor: .top)
            }
        }
    }

    private var timeGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(
                        width: timeGutterWidth,
                        height: hourHeight,
                        alignment: .topTrailing
                    )
                    .offset(y: -6)
                    .padding(.trailing, 5)
                    .id("calendar.hour.\(hour)")
            }
        }
        .frame(width: timeGutterWidth, height: hourHeight * 24, alignment: .topTrailing)
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
            .contentShape(Rectangle())
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
        let height = max(24, CGFloat(endMinute - startMinute) / 60 * hourHeight)
        let spacing: CGFloat = 2
        let available = max(1, width - spacing * CGFloat(placement.columnCount + 1))
        let blockWidth = available / CGFloat(placement.columnCount)
        let x = spacing + CGFloat(placement.column) * (blockWidth + spacing)

        return Button {
            onOpen(entry)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(height < 42 ? 1 : 2)
                if height >= 42 {
                    Text(entry.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9))
                        .opacity(0.76)
                }
            }
            .foregroundStyle(colorForEntry(entry))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                colorForEntry(entry).opacity(entry.status == .completed ? 0.10 : 0.18),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorForEntry(entry))
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }
            .opacity(entry.status == .completed ? 0.62 : (entry.isProjected ? 0.72 : 1))
        }
        .buttonStyle(.plain)
        .frame(width: blockWidth, height: height)
        .offset(x: x, y: y)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    guard entry.isEditableOccurrence else { return }
                    let minuteDelta = Int((value.translation.height / hourHeight * 60) / 15) * 15
                    guard minuteDelta != 0 else { return }
                    let newStart = calendar.date(
                        byAdding: .minute,
                        value: minuteDelta,
                        to: entry.start
                    ) ?? entry.start
                    let newEnd = calendar.date(
                        byAdding: .minute,
                        value: minuteDelta,
                        to: entry.end
                    ) ?? entry.end
                    withAnimation(reduceMotion ? nil : .smooth) {
                        onReschedule(entry, newStart, newEnd)
                    }
                }
        )
        .overlay(alignment: .bottom) {
            if entry.isEditableOccurrence {
                Capsule()
                    .fill(colorForEntry(entry).opacity(0.7))
                    .frame(width: 22, height: 3)
                    .padding(.bottom, 2)
                    .contentShape(Rectangle().inset(by: -8))
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onEnded { value in
                                let minuteDelta =
                                    Int((value.translation.height / hourHeight * 60) / 15) * 15
                                guard minuteDelta != 0 else { return }
                                let candidate = calendar.date(
                                    byAdding: .minute,
                                    value: minuteDelta,
                                    to: entry.end
                                ) ?? entry.end
                                let minimum = calendar.date(
                                    byAdding: .minute,
                                    value: 15,
                                    to: entry.start
                                ) ?? entry.end
                                withAnimation(reduceMotion ? nil : .smooth) {
                                    onReschedule(entry, entry.start, max(candidate, minimum))
                                }
                            }
                    )
                    .accessibilityHidden(true)
            }
        }
        .contextMenu {
            Button {
                onDuplicate(entry)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }
        .accessibilityLabel("\(entry.title), \(entry.start.formatted(date: .omitted, time: .shortened))")
        .accessibilityHint(entry.isEditableOccurrence ? "Drag vertically to reschedule" : "")
        .accessibilityIdentifier(
            timelineEntryIdentifier(entry, day: day)
        )
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
