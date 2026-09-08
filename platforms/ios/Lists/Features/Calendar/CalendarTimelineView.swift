import SwiftUI

enum CalendarTimelinePolicy {
    struct Placement: Identifiable {
        let entry: CalendarEntry
        let column: Int
        let columnCount: Int

        var id: CalendarEntry.ID { entry.id }
    }

    static func placements(entries source: [CalendarEntry]) -> [Placement] {
        let entries = source
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
                clusterEnd = max(clusterEnd, CalendarTimelinePolicy.layoutEnd(entry))
            } else {
                clusters.append(cluster)
                cluster = [entry]
                clusterEnd = CalendarTimelinePolicy.layoutEnd(entry)
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
                    columnEnds[available] = CalendarTimelinePolicy.layoutEnd(entry)
                } else {
                    columnEnds.append(CalendarTimelinePolicy.layoutEnd(entry))
                }
                assignments.append((entry, column))
            }
            return assignments.map {
                Placement(entry: $0.0, column: $0.1, columnCount: max(1, columnEnds.count))
            }
        }
    }

    static let minuteIncrement = 15
    static let minimumEventDuration = 15

    static func initialHour(
        for day: Date,
        entries: [CalendarEntry],
        now: Date,
        calendar: Calendar
    ) -> Int {
        if calendar.isDate(day, inSameDayAs: now) {
            return max(0, calendar.component(.hour, from: now) - 2)
        }
        if let firstTimed = entries.filter({ !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: day) }).min(by: { $0.start < $1.start }) {
            return max(0, calendar.component(.hour, from: firstTimed.start) - 2)
        }
        return 7
    }

    static func canResize(_ entry: CalendarEntry) -> Bool {
        entry.isEditableOccurrence && entry.type == .event
    }

    static func snappedMinuteDelta(for translation: CGFloat, hourHeight: CGFloat) -> Int {
        let raw = Double(translation / hourHeight * 60)
        return Int((raw / Double(minuteIncrement)).rounded()) * minuteIncrement
    }

    static func clampedStartDelta(_ delta: Int, durationMinutes: Int) -> Int {
        min(delta, max(0, durationMinutes - minimumEventDuration))
    }

    static func clampedEndDelta(_ delta: Int, durationMinutes: Int) -> Int {
        max(delta, -max(0, durationMinutes - minimumEventDuration))
    }

    static func wallMinute(_ date: Date, on day: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: day)
        guard date > start else { return 0 }
        guard calendar.isDate(date, inSameDayAs: day) else { return 24 * 60 }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func date(on day: Date, minute: Int, calendar: Calendar) -> Date {
        let clamped = min(23 * 60 + 45, max(0, minute))
        return calendar.date(
            bySettingHour: clamped / 60, minute: clamped % 60, second: 0,
            of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first
        ) ?? calendar.startOfDay(for: day)
    }

    /// Collision space is visual only; it never becomes a task's duration.
    static func layoutEnd(_ entry: CalendarEntry) -> Date {
        entry.isTimeMarker ? entry.start.addingTimeInterval(30 * 60) : entry.end
    }

    static func movedInterval(_ entry: CalendarEntry, minutes: Int, calendar: Calendar) -> DateInterval {
        if minutes == 0 { return DateInterval(start: entry.start, end: entry.end) }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: entry.start)
        let total = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) + minutes
        let dayOffset = Int(floor(Double(total) / 1440))
        let minute = total - dayOffset * 1440
        let day = calendar.date(byAdding: .day, value: dayOffset, to: entry.start) ?? entry.start
        let start = calendar.date(
            bySettingHour: minute / 60, minute: minute % 60, second: parts.second ?? 0,
            of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first
        ) ?? entry.start
        return DateInterval(start: start, duration: max(0, entry.end.timeIntervalSince(entry.start)))
    }
}

struct CalendarTimelineView: View {
    private struct DayPage: Identifiable {
        let days: [Date]
        var id: Date { days[0] }
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
    var visibleColumnCount = 1
    var scrollRequestID = 0
    var onVisibleRangeChange: (Date) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPage: Date?
    @State private var selectedEntryID: CalendarEntry.ID?
    @GestureState private var pageDragOffset: CGFloat = 0

    private let hourHeight: CGFloat = 64
    private let timeGutterWidth: CGFloat = 60

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(pages) { page in
                    timelinePage(page)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height,
                            alignment: .top
                        )
                }
            }
            .offset(
                x: -CGFloat(selectedPageIndex) * geometry.size.width + pageDragOffset
            )
            .animation(reduceMotion ? nil : .smooth, value: selectedPageIndex)
            .simultaneousGesture(pageGesture(pageWidth: geometry.size.width))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            if selectedEntryID != nil {
                HStack {
                    Text("Drag to move. Use handles to resize events.")
                        .font(.caption)
                    Spacer()
                    Button("Done") { selectedEntryID = nil }
                        .accessibilityIdentifier("calendar.timeline.edit.done")
                }
                .padding(10)
                .background(.bar)
            }
        }
        .accessibilityIdentifier(
            visibleColumnCount == 2
                ? "calendar.timeline.two-day.pager"
                : "calendar.timeline.pager"
        )
        .onAppear { selectPage(containing: selectedDate) }
        .onChange(of: selectedDate) {
            selectPage(containing: selectedDate)
        }
        .onChange(of: selectedPage) { _, page in
            guard let page else { return }
            selectedEntryID = nil
            onVisibleRangeChange(page)
        }
        .onChange(of: scrollRequestID) { selectedEntryID = nil }
    }

    private var pages: [DayPage] {
        guard !days.isEmpty else { return [] }
        let count = max(1, visibleColumnCount)
        let normalized = calendar.startOfDay(for: selectedDate)
        let selectedIndex = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: normalized) })
            ?? days.indices.min(by: {
                abs(days[$0].timeIntervalSince(normalized)) < abs(days[$1].timeIntervalSince(normalized))
            })
            ?? days.startIndex

        return (-12...12).compactMap { offset in
            let start = selectedIndex + offset * count
            guard days.indices.contains(start) else { return nil }
            let end = min(days.endIndex, start + count)
            let pageDays = Array(days[start..<end])
            guard pageDays.count == count else { return nil }
            return DayPage(days: pageDays)
        }
    }

    private var selectedPageIndex: Int {
        guard let selectedPage,
              let index = pages.firstIndex(where: { $0.id == selectedPage }) else {
            return pages.firstIndex(where: { page in
                page.days.contains(where: { calendar.isDate($0, inSameDayAs: selectedDate) })
            }) ?? 0
        }
        return index
    }

    private func timelinePage(_ page: DayPage) -> some View {
        VStack(spacing: 0) {
            pageHeader(page.days)
            allDayLane(page.days)
            Divider()
            pageTimeline(page.days)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pageHeader(_ pageDays: [Date]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeGutterWidth)
            ForEach(pageDays, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption.weight(.semibold))
                    Text(day.formatted(.dateTime.day()))
                        .font(.title3.weight(calendar.isDateInToday(day) ? .bold : .medium))
                }
                .foregroundStyle(calendar.isDateInToday(day) ? tint : .primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color(.secondarySystemBackground).opacity(0.55))
                .overlay(alignment: .leading) {
                    Divider()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityIdentifier(
                    "calendar.timeline.day.\(CalendarDateMath.dayIdentifier(day, calendar: calendar))"
                )
            }
        }
        .frame(height: 48)
        .background(.bar)
    }

    @ViewBuilder
    private func allDayLane(_ pageDays: [Date]) -> some View {
        let hasEntries = pageDays.contains { day in
            index.entries(on: day).contains(where: \.isAllDay)
        }
        if hasEntries {
            let rowCount = pageDays.map { index.entries(on: $0).filter(\.isAllDay).count }.max() ?? 0
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    Text("All day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: timeGutterWidth - 4, alignment: .trailing)
                        .padding(.top, 7)
                        .padding(.trailing, 4)

                    ForEach(pageDays, id: \.self) { day in
                        let entries = index.entries(on: day).filter(\.isAllDay)
                        VStack(spacing: 4) {
                            ForEach(entries) { entry in
                                CalendarEntryChip(
                                    entry: entry,
                                    color: colorForEntry(entry),
                                    compact: false,
                                    onOpen: { onOpen(entry) },
                                    onDuplicate: { onDuplicate(entry) },
                                    instanceIdentifier: timelineEntryIdentifier(entry, day: day)
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(4)
                        .overlay(alignment: .leading) { Divider() }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: min(132, CGFloat(rowCount) * 30 + 8))
            .background(Color(.secondarySystemBackground).opacity(0.55))
            .accessibilityIdentifier("calendar.timeline.allday")
        }
    }

    private func pageTimeline(_ pageDays: [Date]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    timeGutter
                    GeometryReader { geometry in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(pageDays, id: \.self) { day in
                                dayColumn(day)
                                    .frame(width: geometry.size.width / CGFloat(pageDays.count))
                                    .overlay(alignment: .leading) { Divider() }
                            }
                        }
                    }
                }
                .frame(height: hourHeight * 24)
                .padding(.bottom, 100)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollDisabled(selectedEntryID != nil)
            .onAppear { scrollToInitialHour(for: pageDays, using: proxy, animated: false) }
            .onChange(of: scrollRequestID) {
                scrollToInitialHour(for: pageDays, using: proxy, animated: true)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var timeGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
                    .padding(.trailing, 7)
                    .frame(width: timeGutterWidth, height: hourHeight, alignment: .topTrailing)
                    .id("calendar.hour.\(hour)")
            }
        }
        .frame(width: timeGutterWidth, height: hourHeight * 24, alignment: .topTrailing)
        .accessibilityHidden(true)
    }

    private func dayColumn(_ day: Date) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                hourGrid(day)

                ForEach(CalendarTimelinePolicy.placements(entries: index.entries(on: day))) { placement in
                    timedBlock(placement, day: day, width: geometry.size.width)
                        .zIndex(selectedEntryID == placement.entry.id ? 2 : 1)
                }

                if calendar.isDateInToday(day) {
                    currentTimeLine
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.timeline.grid")
    }

    private func hourGrid(_ day: Date) -> some View {
        ZStack(alignment: .top) {
            ForEach(0...24, id: \.self) { hour in
                Rectangle()
                    .fill(Color.secondary.opacity(hour == 0 ? 0.25 : 0.13))
                    .frame(height: 0.5)
                    .offset(y: CGFloat(hour) * hourHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(.rect)
        .simultaneousGesture(
            TapGesture().onEnded { selectedEntryID = nil }
        )
        .gesture(createGesture(on: day))
        .accessibilityHidden(true)
    }

    private func timedBlock(
        _ placement: CalendarTimelinePolicy.Placement,
        day: Date,
        width: CGFloat
    ) -> some View {
        let entry = placement.entry
        let startMinute = clippedMinute(entry.start, on: day)
        let endMinute = max(startMinute + 20, clippedMinute(entry.end, on: day, isEnd: true))
        let y = CGFloat(startMinute) / 60 * hourHeight
        let height = entry.isTimeMarker ? 32 : max(28, CGFloat(endMinute - startMinute) / 60 * hourHeight)
        let spacing: CGFloat = 3
        let available = max(1, width - spacing * CGFloat(placement.columnCount + 1))
        let blockWidth = available / CGFloat(placement.columnCount)
        let x = spacing + CGFloat(placement.column) * (blockWidth + spacing)
        let isSelected = selectedEntryID == entry.id

        return CalendarTimelineEntryBlock(
            entry: entry,
            color: colorForEntry(entry),
            height: height,
            selected: isSelected,
            canResize: CalendarTimelinePolicy.canResize(entry),
            onTap: { selectedEntryID = nil; onOpen(entry) },
            onSelect: { selectedEntryID = entry.id },
            onDeselect: { selectedEntryID = nil },
            onDuplicate: { onDuplicate(entry) },
            onMove: { move(entry, by: $0) },
            onResizeStart: { resizeStart(entry, by: $0) },
            onResizeEnd: { resizeEnd(entry, by: $0) }
        )
        .frame(width: blockWidth)
        .offset(x: x, y: y)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(timelineEntryIdentifier(entry, day: day))
    }

    private var currentTimeLine: some View {
        let now = Date.now
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return HStack(spacing: 0) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Rectangle().fill(Color.red).frame(height: 1)
        }
        .offset(x: -3, y: CGFloat(minute) / 60 * hourHeight)
        .accessibilityHidden(true)
    }

    private func selectPage(containing date: Date) {
        guard let page = pages.first(where: { page in
            page.days.contains(where: { calendar.isDate($0, inSameDayAs: date) })
        }) else { return }
        if selectedPage != page.id {
            selectedPage = page.id
        }
    }

    private func pageGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .updating($pageDragOffset) { value, state, _ in
                guard selectedEntryID == nil else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard selectedEntryID == nil,
                      abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > pageWidth * 0.18 else { return }
                let direction = value.translation.width < 0 ? 1 : -1
                let target = min(max(0, selectedPageIndex + direction), pages.count - 1)
                guard pages.indices.contains(target) else { return }
                selectedPage = pages[target].id
            }
    }

    private func scrollToInitialHour(
        for pageDays: [Date],
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let firstDay = pageDays.first ?? selectedDate
        let entries = pageDays.flatMap { index.entries(on: $0) }
        let hour = CalendarTimelinePolicy.initialHour(
            for: firstDay,
            entries: entries,
            now: .now,
            calendar: calendar
        )
        if animated && !reduceMotion {
            withAnimation(.smooth) { proxy.scrollTo("calendar.hour.\(hour)", anchor: .top) }
        } else {
            proxy.scrollTo("calendar.hour.\(hour)", anchor: .top)
        }
    }

    private func createGesture(on day: Date) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                selectedEntryID = nil
                onCreateAt(date(on: day, y: drag.startLocation.y))
            }
    }

    private func move(_ entry: CalendarEntry, by minuteDelta: Int) {
        guard entry.isEditableOccurrence, minuteDelta != 0 else { return }
        selectedEntryID = nil
        let interval = CalendarTimelinePolicy.movedInterval(entry, minutes: minuteDelta, calendar: calendar)
        onReschedule(entry, interval.start, interval.end)
    }

    private func resizeStart(_ entry: CalendarEntry, by minuteDelta: Int) {
        guard CalendarTimelinePolicy.canResize(entry), minuteDelta != 0 else { return }
        selectedEntryID = nil
        let candidate = calendar.date(byAdding: .minute, value: minuteDelta, to: entry.start)
            ?? entry.start
        let latest = calendar.date(
            byAdding: .minute,
            value: -CalendarTimelinePolicy.minimumEventDuration,
            to: entry.end
        ) ?? entry.start
        onReschedule(entry, min(candidate, latest), entry.end)
    }

    private func resizeEnd(_ entry: CalendarEntry, by minuteDelta: Int) {
        guard CalendarTimelinePolicy.canResize(entry), minuteDelta != 0 else { return }
        selectedEntryID = nil
        let candidate = calendar.date(byAdding: .minute, value: minuteDelta, to: entry.end)
            ?? entry.end
        let minimum = calendar.date(
            byAdding: .minute,
            value: CalendarTimelinePolicy.minimumEventDuration,
            to: entry.start
        ) ?? entry.end
        onReschedule(entry, entry.start, max(candidate, minimum))
    }

    private func clippedMinute(_ date: Date, on day: Date, isEnd: Bool = false) -> Int {
        CalendarTimelinePolicy.wallMinute(date, on: day, calendar: calendar)
    }

    private func date(on day: Date, y: CGFloat) -> Date {
        let rawMinutes = Int(max(0, min(hourHeight * 24, y)) / hourHeight * 60)
        let rounded = min(23 * 60 + 45, max(0, Int(round(Double(rawMinutes) / 15)) * 15))
        return CalendarTimelinePolicy.date(on: day, minute: rounded, calendar: calendar)
    }

    private func hourLabel(_ hour: Int) -> String {
        guard let date = calendar.date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: hour)
        ) else { return "\(hour)" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func timelineEntryIdentifier(_ entry: CalendarEntry, day: Date) -> String {
        let dayID = CalendarDateMath.dayIdentifier(day, calendar: calendar)
        return "calendar.timeline.entry.\(entry.itemId.uuidString).\(entry.id.source.rawValue).\(dayID)"
    }
}

private struct CalendarTimelineEntryBlock: View {
    let entry: CalendarEntry
    let color: Color
    let height: CGFloat
    let selected: Bool
    let canResize: Bool
    let onTap: () -> Void
    let onSelect: () -> Void
    let onDeselect: () -> Void
    let onDuplicate: () -> Void
    let onMove: (Int) -> Void
    let onResizeStart: (Int) -> Void
    let onResizeEnd: (Int) -> Void

    @GestureState private var topResizeMinutes = 0
    @GestureState private var bottomResizeMinutes = 0
    @State private var moveMinutes = 0

    private let hourHeight: CGFloat = 64

    var body: some View {
        let duration = max(
            CalendarTimelinePolicy.minimumEventDuration,
            Int(entry.end.timeIntervalSince(entry.start) / 60)
        )
        let topDelta = CalendarTimelinePolicy.clampedStartDelta(
            topResizeMinutes,
            durationMinutes: duration
        )
        let bottomDelta = CalendarTimelinePolicy.clampedEndDelta(
            bottomResizeMinutes,
            durationMinutes: duration
        )
        let displayHeight = max(
            16,
            height + CGFloat(bottomDelta - topDelta) / 60 * hourHeight
        )

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                if entry.isTimeMarker {
                    Text(CalendarTimelinePolicy.movedInterval(entry, minutes: moveMinutes, calendar: .current).start, format: .dateTime.hour().minute())
                        .font(.caption2)
                }
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(displayHeight < 44 ? 1 : 2)
                if !entry.isTimeMarker && displayHeight >= 44 {
                    Text(timeRange(topDelta: topDelta, bottomDelta: bottomDelta))
                        .font(.caption2)
                        .opacity(0.76)
                }
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                color.opacity(entry.isTimeMarker ? 0 : (entry.status == .completed ? 0.10 : 0.18)),
                in: .rect(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? color : .clear, lineWidth: 2)
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3, height: entry.isTimeMarker ? 8 : nil)
                    .padding(.vertical, 2)
            }
            .opacity(entry.status == .completed ? 0.62 : (entry.isProjected ? 0.72 : 1))
        }
        .frame(height: displayHeight)
        .offset(y: CGFloat(topDelta + moveMinutes) / 60 * hourHeight)
        .contentShape(Rectangle())
        .overlay {
            CalendarTimelineInteraction(
                editable: entry.isEditableOccurrence,
                selected: selected,
                onTap: onTap,
                onSelect: onSelect,
                onPreview: { translation in
                    moveMinutes = CalendarTimelinePolicy.snappedMinuteDelta(for: translation, hourHeight: hourHeight)
                },
                onFinish: { translation in
                    moveMinutes = 0
                    guard let translation else { onDeselect(); return }
                    let delta = CalendarTimelinePolicy.snappedMinuteDelta(for: translation, hourHeight: hourHeight)
                    if delta != 0 { onDeselect(); onMove(delta) }
                }
            )
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .overlay(alignment: .topTrailing) {
            if selected && canResize {
                resizeHandle(
                    identifier: "calendar.timeline.resize.start",
                    gesture: startResizeGesture(duration: duration)
                )
                .offset(x: 3, y: -6)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if selected && canResize {
                resizeHandle(
                    identifier: "calendar.timeline.resize.end",
                    gesture: endResizeGesture(duration: duration)
                )
                .offset(x: -3, y: 6)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(entry.isEditableOccurrence ? "Tap to open. Hold to move or resize." : "Opens occurrence details.")
        .accessibilityActions {
            if entry.isEditableOccurrence {
                Button("Move 15 minutes earlier") { onMove(-15) }
                Button("Move 15 minutes later") { onMove(15) }
            }
            if canResize {
                Button("Start 15 minutes earlier") { onResizeStart(-15) }
                Button("Start 15 minutes later") { onResizeStart(15) }
                Button("Shorten by 15 minutes") { onResizeEnd(-15) }
                Button("Extend by 15 minutes") { onResizeEnd(15) }
            }
            Button("Duplicate", action: onDuplicate)
        }
    }

    private func resizeHandle<G: Gesture>(identifier: String, gesture: G) -> some View {
        Circle()
            .fill(Color(.systemBackground))
            .frame(width: 12, height: 12)
            .overlay { Circle().stroke(color, lineWidth: 2) }
            .contentShape(.rect.inset(by: -12))
            .gesture(gesture)
            .accessibilityLabel(identifier.hasSuffix("start") ? "Resize event start" : "Resize event end")
            .accessibilityIdentifier(identifier)
    }

    private func startResizeGesture(duration: Int) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($topResizeMinutes) { value, state, _ in
                let delta = CalendarTimelinePolicy.snappedMinuteDelta(
                    for: value.translation.height,
                    hourHeight: hourHeight
                )
                state = CalendarTimelinePolicy.clampedStartDelta(delta, durationMinutes: duration)
            }
            .onEnded { value in
                onDeselect()
                let delta = CalendarTimelinePolicy.snappedMinuteDelta(
                    for: value.translation.height,
                    hourHeight: hourHeight
                )
                onResizeStart(CalendarTimelinePolicy.clampedStartDelta(
                    delta,
                    durationMinutes: duration
                ))
            }
    }

    private func endResizeGesture(duration: Int) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($bottomResizeMinutes) { value, state, _ in
                let delta = CalendarTimelinePolicy.snappedMinuteDelta(
                    for: value.translation.height,
                    hourHeight: hourHeight
                )
                state = CalendarTimelinePolicy.clampedEndDelta(delta, durationMinutes: duration)
            }
            .onEnded { value in
                onDeselect()
                let delta = CalendarTimelinePolicy.snappedMinuteDelta(
                    for: value.translation.height,
                    hourHeight: hourHeight
                )
                onResizeEnd(CalendarTimelinePolicy.clampedEndDelta(
                    delta,
                    durationMinutes: duration
                ))
            }
    }

    private var accessibilityLabel: String {
        let time = entry.start.formatted(date: .omitted, time: .shortened)
        let source = entry.isProjected ? ", future occurrence" : ""
        if entry.isTimeMarker { return "\(entry.title), due \(time)\(source)" }
        return "\(entry.title), \(time) to \(entry.end.formatted(date: .omitted, time: .shortened))\(source)"
    }

    private func timeRange(topDelta: Int, bottomDelta: Int) -> String {
        let moved = CalendarTimelinePolicy.movedInterval(entry, minutes: moveMinutes, calendar: .current)
        let start = Calendar.current.date(byAdding: .minute, value: topDelta, to: moved.start)
            ?? moved.start
        let end = Calendar.current.date(byAdding: .minute, value: bottomDelta, to: moved.end)
            ?? moved.end
        return "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }
}
