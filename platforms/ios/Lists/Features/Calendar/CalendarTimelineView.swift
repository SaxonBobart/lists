import SwiftUI

enum CalendarTimelinePolicy {
    struct Placement: Identifiable {
        let entry: CalendarEntry
        let column: Int
        let columnCount: Int
        let staggered: Bool

        var id: CalendarEntry.ID { entry.id }
    }

    static func placements(entries source: [CalendarEntry], visibleDayStart: Date? = nil) -> [Placement] {
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
            // Leave every title accessible when starts coincide or are very close.
            // Otherwise preserve width and stack later cards over earlier cards.
            let staggered = !cluster.contains(where: \.isTimeMarker) && zip(cluster, cluster.dropFirst()).allSatisfy {
                let first = max($0.start, visibleDayStart ?? $0.start)
                let second = max($1.start, visibleDayStart ?? $1.start)
                return second.timeIntervalSince(first) >= 30 * 60
            }
            return assignments.map {
                Placement(entry: $0.0, column: $0.1, columnCount: max(1, columnEnds.count), staggered: staggered)
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

@Observable final class CalendarPagingState {
    var progress: CGFloat = 0
}

struct CalendarTimelineView: View {
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
    var onPageProgress: (CGFloat) -> Void = { _ in }

    var paging: CalendarPagingState? = nil
    @State private var localPaging = CalendarPagingState()
    private var pageState: CalendarPagingState { paging ?? localPaging }
    @State private var selection: String?
    @State private var gesture: CalendarTimelineGesture?
    @State private var edgeAnchor: Date?
    @State private var editingAllDayHeight: CGFloat?

    private var allDayHeight: CGFloat {
        let count = pageDays.map { index.entries(on: $0).filter(\.isAllDay).count }.max() ?? 0
        return count > 0 ? min(112, CGFloat(count) * 28 + 5) : 0
    }

    private var pagingAllDayHeight: CGFloat {
        guard let first = pageDays.first, let start = days.firstIndex(of: first) else { return allDayHeight }
        let whole = Int(floor(pageState.progress))
        let fraction = pageState.progress - CGFloat(whole)
        func height(at offset: Int) -> CGFloat {
            let destination = CalendarTimelineGeometry.pageOffset(current: start, direction: offset,
                columns: visibleColumnCount, count: days.count, editing: false)
            let incoming = CalendarTimelineGeometry.neighboringDays(in: days, start: destination, columns: visibleColumnCount, page: 0)
            let count = incoming.map { index.entries(on: $0).filter(\.isAllDay).count }.max() ?? 0
            return count > 0 ? min(112, CGFloat(count) * 28 + 5) : 0
        }
        return height(at: whole) + (height(at: whole + 1) - height(at: whole)) * fraction
    }

    private var pageDays: [Date] {
        let anchor = edgeAnchor ?? calendar.startOfDay(for: selectedDate)
        return Array(days.filter { $0 >= anchor }.prefix(max(1, visibleColumnCount)))
    }

    var body: some View {
        GeometryReader { geometry in
            let targets = CalendarTimelineGeometry.targets(days: pageDays, index: index, width: geometry.size.width, calendar: calendar)
            let preview = gesture.flatMap {
                CalendarTimelineGeometry.preview($0, days: pageDays, width: geometry.size.width, calendar: calendar)
            }
            let pageRadius = days.count / max(1, pageDays.count) + 1
            let canvases = Dictionary(uniqueKeysWithValues: (-pageRadius...pageRadius).map { page in
                let visible = neighboringDays(page)
                return (page, CalendarTimelineCanvas(days: visible,
                    targets: page == 0 ? targets : CalendarTimelineGeometry.targets(days: visible, index: index, width: geometry.size.width, calendar: calendar),
                    preview: page == 0 ? preview : nil, selection: page == 0 ? selection : nil,
                    width: geometry.size.width, calendar: calendar, tint: tint,
                    color: colorForEntry, onOpen: onOpen, onDuplicate: onDuplicate,
                    onAccessibleMove: accessibleMove, onAccessibleResize: accessibleResize))
            })
            VStack(spacing: 0) {
                CalendarTimelinePageStrip(width: geometry.size.width, paging: pageState, columns: pageDays.count) { page in
                    VStack(spacing: 0) {
                        CalendarTimelineDayHeader(days: neighboringDays(page), calendar: calendar)
                        CalendarTimelineAllDayBand(days: neighboringDays(page), index: index, calendar: calendar,
                            height: editingAllDayHeight ?? pagingAllDayHeight,
                            color: colorForEntry, onOpen: onOpen, onDuplicate: onDuplicate)
                    }
                }
                Divider()
                CalendarTimelineScroll(
                    canvas: CalendarTimelineCanvas(days: pageDays, targets: targets, preview: preview,
                        selection: selection, width: geometry.size.width, calendar: calendar, tint: tint,
                        color: colorForEntry, onOpen: { selection = nil; onOpen($0) }, onDuplicate: onDuplicate,
                        onAccessibleMove: accessibleMove, onAccessibleResize: accessibleResize),
                    targets: targets, selection: selection,
                    initialHour: CalendarTimelinePolicy.initialHour(for: pageDays.first ?? selectedDate,
                        entries: pageDays.flatMap { index.entries(on: $0) }, now: .now, calendar: calendar),
                    scrollRequestID: scrollRequestID,
                    onSelect: { selection = $0 },
                    onOpen: { selection = nil; onOpen($0) },
                    onPreview: {
                        if gesture == nil && $0 != nil { editingAllDayHeight = allDayHeight }
                        gesture = $0
                    },
                    onFinish: { finish($0, width: geometry.size.width) },
                    onPage: { shiftPage($0, editing: $1) },
                    onPageProgress: { pageState.progress = $0; onPageProgress($0) },
                    canPage: { direction in
                        guard let first = pageDays.first, let start = days.firstIndex(of: first) else { return false }
                        return CalendarTimelineGeometry.pageOffset(current: start, direction: direction,
                            columns: visibleColumnCount, count: days.count, editing: false) == start + direction
                    },
                    pagingContent: AnyView(CalendarTimelinePageStrip(width: geometry.size.width, paging: pageState, columns: pageDays.count) { page in
                        canvases[page]
                    })
                )
                .background(CalendarTimelineGridBackdrop(width: geometry.size.width, columns: pageDays.count, paging: pageState))
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.17))
                    .frame(width: 0.5)
                    .offset(x: CalendarTimelineGeometry.gutter)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier("calendar.timeline.pager")
        .onChange(of: scrollRequestID) { pageState.progress = 0; onPageProgress(0); selection = nil; gesture = nil; edgeAnchor = nil; editingAllDayHeight = nil }
        .onChange(of: selectedDate) { if gesture == nil { pageState.progress = 0; onPageProgress(0); edgeAnchor = nil; selection = nil } }
        .onChange(of: visibleColumnCount) { pageState.progress = 0; onPageProgress(0); selection = nil; gesture = nil; edgeAnchor = nil; editingAllDayHeight = nil }
    }

    private func neighboringDays(_ page: Int) -> [Date] {
        guard page != 0 else { return pageDays }
        guard let first = pageDays.first, let start = days.firstIndex(of: first) else { return [] }
        return CalendarTimelineGeometry.neighboringDays(in: days, start: start, columns: pageDays.count, page: page)
    }

    private func shiftPage(_ direction: Int, editing: Bool) {
        guard let first = pageDays.first,
              let offset = days.firstIndex(of: first) else { return }
        let next = CalendarTimelineGeometry.pageOffset(current: offset, direction: direction,
            columns: visibleColumnCount, count: days.count, editing: editing)
        guard days.indices.contains(next) else { return }
        edgeAnchor = days[next]
        if !editing { selection = nil }
        onVisibleRangeChange(days[next])
    }

    private func finish(_ value: CalendarTimelineGesture?, width: CGFloat) {
        defer { gesture = nil; editingAllDayHeight = nil }
        guard let value, let preview = CalendarTimelineGeometry.preview(value, days: pageDays, width: width, calendar: calendar) else {
            selection = nil
            return
        }
        if value.mode == .create {
            selection = nil
            onCreateAt(preview.start)
        } else if let entry = value.target?.entry {
            // A stationary hold only selects; it must not round an existing exact time.
            guard CalendarTimelineGeometry.shouldCommit(value, preview: preview, calendar: calendar) else { return }
            selection = (value.mode == .start || value.mode == .end) ? value.target?.id : nil
            if preview.start != entry.start || preview.end != entry.end {
                onReschedule(entry, preview.start, preview.end)
            }
        }
    }

    private func accessibleResize(_ entry: CalendarEntry, _ mode: CalendarTimelineGestureMode, _ minutes: Int) {
        guard CalendarTimelinePolicy.canResize(entry) else { return }
        let start = mode == .start ? min(entry.start.addingTimeInterval(Double(minutes) * 60), entry.end.addingTimeInterval(-900)) : entry.start
        let end = mode == .end ? max(entry.end.addingTimeInterval(Double(minutes) * 60), entry.start.addingTimeInterval(900)) : entry.end
        onReschedule(entry, start, end)
    }

    private func accessibleMove(_ entry: CalendarEntry, _ minutes: Int) {
        guard entry.isEditableOccurrence else { return }
        let moved = CalendarTimelinePolicy.movedInterval(entry, minutes: minutes, calendar: calendar)
        onReschedule(entry, moved.start, moved.end)
    }
}

/// Fixed viewport backing keeps day boundaries visible through vertical bounce.
private struct CalendarTimelineGridBackdrop: View {
    let width: CGFloat
    let columns: Int
    let paging: CalendarPagingState

    var body: some View {
        let columnWidth = max(1, (width - CalendarTimelineGeometry.gutter) / CGFloat(max(1, columns)))
        let fraction = paging.progress.truncatingRemainder(dividingBy: 1)
        ZStack(alignment: .leading) {
            Color(.systemBackground)
            ForEach(-1...(columns + 1), id: \.self) { column in
                Rectangle().fill(Color.primary.opacity(0.17))
                    .frame(width: 0.5)
                    .offset(x: CalendarTimelineGeometry.gutter + (CGFloat(column) - fraction) * columnWidth)
            }
            Color(.systemBackground).frame(width: CalendarTimelineGeometry.gutter)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One continuous date surface, clipped after removing each page's repeated time gutter.
private struct CalendarTimelinePageStrip<Content: View>: View {
    let width: CGFloat
    let paging: CalendarPagingState
    let columns: Int
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        let gutter = CalendarTimelineGeometry.gutter
        let pageWidth = max(1, width - gutter)
        let firstPage = Int(floor(paging.progress / CGFloat(max(1, columns)))) - 1
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(firstPage...(firstPage + 2), id: \.self) { page in
                    content(page)
                        .frame(width: width)
                        .offset(x: -gutter)
                        .frame(width: pageWidth, alignment: .leading)
                        .clipped()
                        .accessibilityHidden(page != 0)
                        .allowsHitTesting(page == 0)
                }
            }
            .offset(x: CGFloat(firstPage) * pageWidth - paging.progress * pageWidth / CGFloat(max(1, columns)))
            .frame(width: pageWidth, alignment: .leading)
            .clipped()
            .offset(x: gutter)
            content(0)
                .frame(width: width)
                .frame(width: gutter, alignment: .leading)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: width, alignment: .leading)
        .clipped()
    }
}

private struct CalendarTimelineDayHeader: View {
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight = 38.0
    let days: [Date]
    let calendar: Calendar
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CalendarTimelineGeometry.gutter, height: rowHeight)
            ForEach(days, id: \.self) { day in
                Text(day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
                    .overlay(alignment: .leading) { Divider() }
                    .accessibilityIdentifier("calendar.timeline.day.\(CalendarDateMath.dayIdentifier(day, calendar: calendar))")
            }
        }
    }
}

private struct CalendarTimelineAllDayBand: View {
    let days: [Date]
    let index: CalendarEntryIndex
    let calendar: Calendar
    let height: CGFloat
    let color: (CalendarEntry) -> Color
    let onOpen: (CalendarEntry) -> Void
    let onDuplicate: (CalendarEntry) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
                Text("all-day")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.secondary)
                    .frame(width: CalendarTimelineGeometry.gutter - 6, alignment: .trailing)
                    .padding(.trailing, 6)
                    .padding(.top, 8)
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            VStack(spacing: 3) {
                                ForEach(index.entries(on: day).filter(\.isAllDay)) { entry in
                                    Button { onOpen(entry) } label: {
                                        Label(entry.title, systemImage: entry.type == .task ? "circle" : "calendar")
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                            .foregroundStyle(color(entry))
                                            .padding(.horizontal, 8)
                                            .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
                                            .background(color(entry).opacity(0.20), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(entry.title), all day")
                                    .accessibilityIdentifier("calendar.allday.\(entry.itemId.uuidString).\(CalendarDateMath.dayIdentifier(day, calendar: calendar))")
                                    .contextMenu {
                                        Button("Duplicate") { onDuplicate(entry) }
                                            .accessibilityIdentifier("calendar.allday.duplicate")
                                    }
                                }
                            }
                            .padding(.horizontal, 3)
                            .frame(maxWidth: .infinity, minHeight: max(0, height - 8), alignment: .top)
                            .overlay(alignment: .leading) { Divider().padding(.vertical, -4) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: height)
                .accessibilityIdentifier("calendar.timeline.allday")
            }
            .frame(height: max(0, height), alignment: .top)
            .clipped()
            .accessibilityHidden(height < 1)
    }
}

struct CalendarTimelineCanvas: View {
    let days: [Date]
    let targets: [CalendarTimelineTarget]
    let preview: CalendarTimelinePreview?
    let selection: String?
    let width: CGFloat
    let calendar: Calendar
    let tint: Color
    let color: (CalendarEntry) -> Color
    let onOpen: (CalendarEntry) -> Void
    let onDuplicate: (CalendarEntry) -> Void
    let onAccessibleMove: (CalendarEntry, Int) -> Void
    let onAccessibleResize: (CalendarEntry, CalendarTimelineGestureMode, Int) -> Void

    var body: some View {
        let columnWidth = (width - CalendarTimelineGeometry.gutter) / CGFloat(max(1, days.count))
        ZStack(alignment: .topLeading) {
            if let activeDay = preview?.day ?? targets.first(where: { $0.id == selection })?.day,
               let column = days.firstIndex(of: activeDay) {
                Rectangle().fill(Color.primary.opacity(0.07))
                    .frame(width: columnWidth, height: CalendarTimelineGeometry.height)
                    .offset(x: CalendarTimelineGeometry.gutter + CGFloat(column) * columnWidth)
            }
            ForEach(0...24, id: \.self) { hour in
                let y = CalendarTimelineGeometry.y(minute: CGFloat(hour * 60))
                Rectangle().fill(Color.primary.opacity(0.17))
                    .frame(width: max(0, width - CalendarTimelineGeometry.gutter), height: 0.5)
                    .offset(x: CalendarTimelineGeometry.gutter, y: y)
                Text(CalendarTimelineGeometry.hourLabel(hour, calendar: calendar))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: CalendarTimelineGeometry.gutter - 7, height: 18, alignment: .trailing)
                    .offset(y: y - 9)
                    .accessibilityHidden(true)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { column, _ in
                Rectangle().fill(Color.primary.opacity(0.17))
                    .frame(width: 0.5, height: CalendarTimelineGeometry.contentHeight)
                    .offset(x: CalendarTimelineGeometry.gutter + CGFloat(column) * columnWidth)
            }
            ForEach(targets) { target in
                if preview?.entry?.id != target.entry.id {
                    CalendarTimelineEventFace(entry: target.entry, color: color(target.entry),
                        start: target.entry.start, end: target.entry.end, selected: selection == target.id)
                        .frame(width: target.frame.width, height: target.frame.height)
                        .offset(x: target.frame.minX, y: target.frame.minY)
                        .accessibilityElement(children: selection == target.id ? .contain : .ignore)
                        .accessibilityLabel(target.entry.title + ", " + target.entry.start.formatted(date: .abbreviated, time: .shortened))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier(target.id)
                        .accessibilityAction { onOpen(target.entry) }
                        .accessibilityActions {
                            if target.entry.isEditableOccurrence {
                                Button("Move 15 minutes earlier") { onAccessibleMove(target.entry, -15) }
                                Button("Move 15 minutes later") { onAccessibleMove(target.entry, 15) }
                            }
                            if CalendarTimelinePolicy.canResize(target.entry) {
                                Button("Start 15 minutes earlier") { onAccessibleResize(target.entry, .start, -15) }
                                Button("Start 15 minutes later") { onAccessibleResize(target.entry, .start, 15) }
                                Button("Shorten by 15 minutes") { onAccessibleResize(target.entry, .end, -15) }
                                Button("Extend by 15 minutes") { onAccessibleResize(target.entry, .end, 15) }
                            }
                            Button("Duplicate") { onDuplicate(target.entry) }
                        }
                }
            }
            if let preview {
                CalendarTimelineEventFace(entry: preview.entry, color: preview.entry.map(color) ?? tint,
                    start: preview.start, end: preview.end, selected: true)
                    .frame(width: preview.frame.width, height: preview.frame.height)
                    .offset(x: preview.frame.minX, y: preview.frame.minY)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("calendar.timeline.preview")
            }
            TimelineView(.everyMinute) { context in
                if let column = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: context.date) }) {
                    let minute = CalendarTimelinePolicy.wallMinute(context.date, on: context.date, calendar: calendar)
                    CalendarTimelineCurrentTime(date: context.date, calendar: calendar,
                        width: width, column: column, columnCount: days.count)
                        .offset(y: CalendarTimelineGeometry.y(minute: CGFloat(minute)))
                }
            }
        }
        .frame(width: width, height: CalendarTimelineGeometry.contentHeight, alignment: .topLeading)
        .background(Color(.systemBackground))
    }
}

/// The gutter clock anchors a quiet cross-column guide; only today's segment
/// carries the full red emphasis. It shares the grid's exact minute coordinate.
struct CalendarTimelineCurrentTime: View {
    @Environment(\.locale) private var locale
    let date: Date
    let calendar: Calendar
    let width: CGFloat
    let column: Int
    let columnCount: Int

    var body: some View {
        let gutter = CalendarTimelineGeometry.gutter
        let columnWidth = (width - gutter) / CGFloat(max(1, columnCount))
        let minute = CGFloat(calendar.component(.minute, from: date))
        let nearestHourDelta = ((minute / 60).rounded() * 60 - minute) / 60 * CalendarTimelineGeometry.hourHeight
        ZStack(alignment: .leading) {
            if abs(nearestHourDelta) < 18 {
                Color(.systemBackground)
                    .frame(width: gutter, height: 18)
                    .offset(y: nearestHourDelta)
            }
            Rectangle().fill(Color.red.opacity(0.12))
                .frame(width: width - gutter, height: 1)
                .offset(x: gutter)
            Rectangle().fill(Color.red)
                .frame(width: columnWidth, height: 1.5)
                .offset(x: gutter + CGFloat(column) * columnWidth)
            Text(date, format: Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.red, in: Capsule())
                .frame(width: gutter, alignment: .trailing)
        }
        .frame(width: width, height: 0, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CalendarTimelineEventFace: View {
    let entry: CalendarEntry?
    let color: Color
    let start: Date
    let end: Date
    let selected: Bool

    var body: some View {
        GeometryReader { geometry in
            let marker = entry?.isTimeMarker == true
            VStack(alignment: .leading, spacing: 2) {
                Text(entry?.title ?? "New event")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(marker ? color : Color.primary)
                    .lineLimit(geometry.size.height < 40 ? 1 : 2)
                if geometry.size.height >= 36 {
                    Text(marker ? start.formatted(date: .omitted, time: .shortened)
                         : "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(marker ? .clear : color.opacity(selected ? 0.30 : 0.18), in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: 3, height: marker ? 7 : nil)
            }
            .overlay { RoundedRectangle(cornerRadius: 5).stroke(selected ? color : .clear, lineWidth: 1.5) }
            .overlay(alignment: .topLeading) {
                if selected && geometry.size.height < 36 {
                    Text(marker ? start.formatted(date: .omitted, time: .shortened)
                         : "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                        .fixedSize()
                        .offset(y: -24)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected && !marker { handle(identifier: "calendar.timeline.resize.start").offset(x: -10, y: -5) }
            }
            .overlay(alignment: .bottomLeading) {
                if selected && !marker { handle(identifier: "calendar.timeline.resize.end").offset(x: 10, y: 5) }
            }
            .opacity(entry?.isProjected == true ? 0.7 : 1)
        }
    }

    private func handle(identifier: String) -> some View {
        Circle().fill(.white).frame(width: 10, height: 10)
            .overlay { Circle().stroke(color, lineWidth: 1.5) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(identifier.hasSuffix("start") ? "Resize event start" : "Resize event end")
            .accessibilityIdentifier(identifier)
    }
}
