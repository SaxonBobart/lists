import SwiftUI
import UIKit

struct CalendarTimelineTarget: Identifiable {
    let entry: CalendarEntry
    let day: Date
    let frame: CGRect
    var id: String { "calendar.timeline.entry.\(entry.itemId.uuidString).\(entry.id.source.rawValue).\(day.timeIntervalSince1970)" }
}

enum CalendarTimelineGestureMode { case move, start, end, create }

struct CalendarTimelineGesture {
    let mode: CalendarTimelineGestureMode
    let target: CalendarTimelineTarget?
    let origin: CGPoint
    var location: CGPoint
}

struct CalendarTimelinePreview {
    let entry: CalendarEntry?
    let day: Date
    let start: Date
    let end: Date
    let frame: CGRect
}

/// The sole conversion between screen geometry and calendar time. Raw geometry
/// stays continuous; only proposed dates are snapped. Storage is never a preview.
enum CalendarTimelineGeometry {
    static let gutter: CGFloat = 56
    static let hourHeight: CGFloat = 64
    static let topInset: CGFloat = 18
    static let height = topInset + 24 * hourHeight
    static let contentHeight = height + 100

    static func y(minute: CGFloat) -> CGFloat { topInset + minute / 60 * hourHeight }
    static func minute(y: CGFloat) -> CGFloat { (y - topInset) / hourHeight * 60 }
    static func snapped(_ minute: CGFloat) -> Int { Int((minute / 15).rounded()) * 15 }
    static func column(x: CGFloat, width: CGFloat, count: Int) -> Int {
        let size = max(1, (width - gutter) / CGFloat(max(1, count)))
        return min(max(0, Int(floor((x - gutter) / size))), max(0, count - 1))
    }

    static func edgeDirection(x: CGFloat, width: CGFloat) -> Int {
        if x < gutter + 18 { return -1 }
        if x > width - 18 { return 1 }
        return 0
    }

    static func edgeScrollSpeed(penetration: CGFloat, elapsed: TimeInterval) -> CGFloat {
        let depth = min(1, max(0, penetration / 72))
        let acceleration = 1 + min(2, max(0, elapsed)) * 1.5
        return min(1000, (80 + 240 * depth * depth) * depth * acceleration)
    }

    static func neighboringDays(in days: [Date], start: Int, columns: Int, page: Int) -> [Date] {
        let lower = start + page * columns
        let upper = lower + columns
        return Array(days[max(0, min(days.count, lower))..<max(0, min(days.count, upper))])
    }

    /// Project release momentum in day-column units. Returning to the origin
    /// with no velocity cancels, regardless of the furthest point of the drag.
    static func destination(progress: CGFloat, velocity: CGFloat, columnWidth: CGFloat) -> Int {
        let projected = progress - velocity * 0.20 / max(1, columnWidth)
        let destination = Int(projected.rounded())
        if destination == 0, abs(progress) * max(1, columnWidth) >= 28, velocity * progress <= 0 {
            return progress < 0 ? -1 : 1
        }
        return destination
    }

    static func adaptiveColumns(width: CGFloat) -> Int {
        max(2, min(7, Int(max(0, width - gutter) / 170)))
    }

    static func pageOffset(current: Int, direction: Int, columns: Int, count: Int, editing: Bool) -> Int {
        return min(max(0, current + direction), max(0, count - columns))
    }

    static func shouldCommit(_ gesture: CalendarTimelineGesture?, preview: CalendarTimelinePreview?, calendar: Calendar) -> Bool {
        guard let gesture, let preview else { return false }
        if gesture.mode == .create { return true }
        guard let target = gesture.target, target.entry.isEditableOccurrence else { return false }
        return abs(gesture.location.x - gesture.origin.x) > 4 || abs(gesture.location.y - gesture.origin.y) > 4
            || !calendar.isDate(preview.day, inSameDayAs: target.day)
    }

    static func selectedMode(at point: CGPoint, target: CalendarTimelineTarget) -> CalendarTimelineGestureMode? {
        guard target.entry.isEditableOccurrence else { return nil }
        if CalendarTimelinePolicy.canResize(target.entry) {
            let top = CGPoint(x: target.frame.maxX - 15, y: target.frame.minY)
            let bottom = CGPoint(x: target.frame.minX + 15, y: target.frame.maxY)
            if abs(point.x - top.x) <= 22 && abs(point.y - top.y) <= 22 { return .start }
            if abs(point.x - bottom.x) <= 22 && abs(point.y - bottom.y) <= 22 { return .end }
        }
        return target.frame.contains(point) ? .move : nil
    }

    static func targets(days: [Date], index: CalendarEntryIndex, width: CGFloat, calendar: Calendar) -> [CalendarTimelineTarget] {
        let columnWidth = max(1, (width - gutter) / CGFloat(max(1, days.count)))
        return days.enumerated().flatMap { column, day in
            CalendarTimelinePolicy.placements(entries: index.entries(on: day), visibleDayStart: calendar.startOfDay(for: day)).map { placement in
                let entry = placement.entry
                let start = CalendarTimelinePolicy.wallMinute(entry.start, on: day, calendar: calendar)
                let end = CalendarTimelinePolicy.wallMinute(entry.end, on: day, calendar: calendar)
                let inset = CGFloat(placement.column) * min(10, columnWidth * 0.4 / CGFloat(max(1, placement.columnCount - 1)))
                let blockWidth = placement.staggered ? max(1, columnWidth - 6 - inset)
                    : max(1, (columnWidth - CGFloat(placement.columnCount + 1) * 3) / CGFloat(placement.columnCount))
                let offset = placement.staggered ? inset : CGFloat(placement.column) * (blockWidth + 3)
                return CalendarTimelineTarget(entry: entry, day: day, frame: CGRect(
                    x: gutter + CGFloat(column) * columnWidth + 3 + offset,
                    y: y(minute: CGFloat(start)), width: blockWidth,
                    height: entry.isTimeMarker ? 32 : max(16, CGFloat(end - start) / 60 * hourHeight)))
            }
        }
    }

    static func preview(_ gesture: CalendarTimelineGesture, days: [Date], width: CGFloat, calendar: Calendar) -> CalendarTimelinePreview? {
        guard !days.isEmpty else { return nil }
        let columnWidth = max(1, (width - gutter) / CGFloat(days.count))
        let destination = days[column(x: gesture.location.x, width: width, count: days.count)]
        let delta = (gesture.location.y - gesture.origin.y) / hourHeight * 60
        if let target = gesture.target {
            let entry = target.entry
            let duration = max(0, entry.end.timeIntervalSince(entry.start))
            switch gesture.mode {
            case .move:
                let raw = min(1425, max(0, minute(y: target.frame.minY) + delta))
                let sourceDay = calendar.startOfDay(for: entry.start)
                let sourceDayOffset = calendar.dateComponents([.day], from: sourceDay, to: target.day).day ?? 0
                let originalMinute = CalendarTimelinePolicy.wallMinute(entry.start, on: entry.start, calendar: calendar)
                let continuationOffset = sourceDayOffset > 0 ? originalMinute - sourceDayOffset * 1440 : 0
                let start = clockDate(on: destination, minute: snapped(raw) + continuationOffset, calendar: calendar)
                let end = start.addingTimeInterval(duration)
                let x = min(width - 16, max(gutter - target.frame.width + 16,
                    gesture.location.x - (gesture.origin.x - target.frame.minX)))
                let remaining = min(1440 - raw, CGFloat(CalendarTimelinePolicy.wallMinute(end, on: destination, calendar: calendar) - snapped(raw)))
                let height = entry.isTimeMarker ? 32 : max(16, remaining / 60 * hourHeight)
                return .init(entry: entry, day: destination, start: start, end: end,
                    frame: CGRect(x: x, y: y(minute: raw), width: target.frame.width, height: height))
            case .start, .end:
                let originalEdge = gesture.mode == .start ? target.frame.minY : target.frame.maxY
                let rawMinute = min(1440, max(0, minute(y: originalEdge) + delta))
                let candidate = clockDate(on: target.day, minute: snapped(rawMinute), calendar: calendar)
                let start = gesture.mode == .start ? min(candidate, entry.end.addingTimeInterval(-900)) : entry.start
                let end = gesture.mode == .end ? max(candidate, entry.start.addingTimeInterval(900)) : entry.end
                let minimumHeight = hourHeight / 4
                let edge = gesture.mode == .start
                    ? min(y(minute: rawMinute), target.frame.maxY - minimumHeight)
                    : max(y(minute: rawMinute), target.frame.minY + minimumHeight)
                let frame = CGRect(x: target.frame.minX,
                    y: gesture.mode == .start ? edge : target.frame.minY,
                    width: target.frame.width,
                    height: gesture.mode == .start ? target.frame.maxY - edge : edge - target.frame.minY)
                return .init(entry: entry, day: target.day, start: start, end: end, frame: frame)
            case .create: return nil
            }
        }
        let raw = min(1380, max(0, minute(y: gesture.location.y) - 30))
        let start = CalendarTimelinePolicy.date(on: destination, minute: min(1425, snapped(raw)), calendar: calendar)
        let x = gutter + CGFloat(column(x: gesture.location.x, width: width, count: days.count)) * columnWidth + 3
        return .init(entry: nil, day: destination, start: start, end: start.addingTimeInterval(3600),
                     frame: CGRect(x: x, y: y(minute: raw), width: columnWidth - 6, height: hourHeight))
    }

    static func clockDate(on day: Date, minute: Int, calendar: Calendar) -> Date {
        let offset = Int(floor(Double(minute) / 1440))
        let withinDay = minute - offset * 1440
        let destination = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: day)) ?? day
        return calendar.date(bySettingHour: withinDay / 60, minute: withinDay % 60, second: 0,
            of: destination, matchingPolicy: .nextTime, repeatedTimePolicy: .first) ?? destination
    }

    static func hourLabel(_ hour: Int, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("j")
        let day = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1))!
        return formatter.string(from: calendar.date(byAdding: .hour, value: hour, to: day)!)
    }
}

/// A stable scroll-view gesture surface survives SwiftUI item relayout and date
/// paging. The hosted canvas only draws; the controller owns touch arbitration.
struct CalendarTimelineScroll: UIViewControllerRepresentable {
    @Environment(\.dynamicTypeSize) var textSize
    @Environment(\.colorScheme) var colorScheme
    let canvas: CalendarTimelineCanvas
    let targets: [CalendarTimelineTarget]
    let selection: String?
    let initialHour: Int
    let scrollRequestID: Int
    let onSelect: (String?) -> Void
    let onOpen: (CalendarEntry) -> Void
    let onPreview: (CalendarTimelineGesture?) -> Void
    let onFinish: (CalendarTimelineGesture?) -> Void
    let onPage: (Int, Bool) -> Void
    var onPageProgress: (CGFloat) -> Void = { _ in }
    var canPage: (Int) -> Bool = { _ in true }
    var pagingContent: AnyView? = nil

    func makeUIViewController(context: Context) -> CalendarTimelineController {
        CalendarTimelineController(configuration: self)
    }

    func updateUIViewController(_ controller: CalendarTimelineController, context: Context) {
        controller.update(self)
    }

    static func dismantleUIViewController(_ controller: CalendarTimelineController, coordinator: ()) {
        controller.stopTracking()
    }
}

final class CalendarTimelineController: UIViewController, UIGestureRecognizerDelegate {
    var configuration: CalendarTimelineScroll
    private let scroll = UIScrollView()
    private let host: UIHostingController<AnyView>
    private var active: CalendarTimelineGesture?
    private var displayLink: CADisplayLink?
    private var edgeSince: CFTimeInterval?
    private var edgeDirection = 0
    private var verticalEdgeDirection = 0
    private var verticalEdgeSince: CFTimeInterval?
    private var lastWindowPoint = CGPoint.zero
    private var didPosition = false
    private var pendingScroll = false
    private var pagePan = false
    private var pageProgress: CGFloat = 0
    private var panOriginProgress: CGFloat = 0
    private var creationMoved = false
    private var feedbackDay = 0
    private var settleDuration: Double = 0.25
    private lazy var pageFeedback = UISelectionFeedbackGenerator(view: view)
    private var settling: CADisplayLink?
    private var settleStart: CFTimeInterval = 0
    private var settleFrom: CGFloat = 0
    private var settleTo: CGFloat = 0
    private var settleDirection = 0
    private lazy var hold = CalendarTimelineHold(target: self, action: #selector(held(_:)))
    private lazy var pan = CalendarTimelinePan(target: self, action: #selector(panned(_:)))
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))

    init(configuration: CalendarTimelineScroll) {
        self.configuration = configuration
        self.host = UIHostingController(rootView: AnyView((configuration.pagingContent ?? AnyView(configuration.canvas)).environment(\.dynamicTypeSize, configuration.textSize).environment(\.colorScheme, configuration.colorScheme)))
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.alwaysBounceVertical = true
        scroll.accessibilityIdentifier = "calendar.timeline.scroll"
        view.addSubview(scroll)
        addChild(host)
        scroll.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.backgroundColor = .clear
        hold.minimumPressDuration = 0.25
        hold.allowableMovement = 10
        hold.delegate = self
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        tap.require(toFail: hold)
        tap.require(toFail: pan)
        scroll.addGestureRecognizer(tap)
        scroll.addGestureRecognizer(hold)
        scroll.addGestureRecognizer(pan)
        scroll.panGestureRecognizer.require(toFail: pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.frame = view.bounds
        let size = CGSize(width: view.bounds.width, height: CalendarTimelineGeometry.contentHeight)
        host.view.frame = CGRect(origin: .zero, size: size)
        scroll.contentSize = size
        if (!didPosition || pendingScroll) && view.bounds.height > 0 {
            didPosition = true
            pendingScroll = false
            let y = CGFloat(configuration.initialHour) * CalendarTimelineGeometry.hourHeight
            scroll.setContentOffset(CGPoint(x: 0, y: min(y, max(0, size.height - scroll.bounds.height))), animated: false)
        }
    }

    func update(_ value: CalendarTimelineScroll) {
        if configuration.canvas.days != value.canvas.days && (settling != nil || pagePan) { stopTracking() }
        if configuration.scrollRequestID != value.scrollRequestID {
            stopTracking()
            pendingScroll = true
        }
        configuration = value
        host.rootView = AnyView((value.pagingContent ?? AnyView(value.canvas)).environment(\.dynamicTypeSize, value.textSize).environment(\.colorScheme, value.colorScheme))
        view.setNeedsLayout()
    }

    private func target(at point: CGPoint) -> CalendarTimelineTarget? {
        configuration.targets.reversed().first { $0.frame.insetBy(dx: 0, dy: -4).contains(point) }
    }

    private func selectedMode(at point: CGPoint) -> (CalendarTimelineTarget, CalendarTimelineGestureMode)? {
        guard let selected = configuration.targets.first(where: { $0.id == configuration.selection }),
              let mode = CalendarTimelineGeometry.selectedMode(at: point, target: selected) else { return nil }
        if mode == .move, target(at: point)?.id != selected.id { return nil }
        return (selected, mode)
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        if settling != nil && recognizer !== pan { return false }
        if recognizer === hold {
            let point = hold.touchDown
            guard point.x >= CalendarTimelineGeometry.gutter else { return false }
            if selectedMode(at: point) != nil { return true }
            if let target = target(at: point) { return target.entry.isEditableOccurrence }
            return point.y >= CalendarTimelineGeometry.topInset && point.y <= CalendarTimelineGeometry.height
        }
        if recognizer === pan {
            guard active == nil else { return false }
            if selectedMode(at: pan.touchDown) != nil { return true }
            let velocity = pan.velocity(in: scroll)
            let horizontal = abs(velocity.x) > abs(velocity.y) * 1.3
            if horizontal {
                settling?.invalidate()
                settling = nil
            }
            return horizontal
        }
        return true
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        if let target = target(at: recognizer.location(in: host.view)) {
            configuration.onOpen(target.entry)
        } else { configuration.onSelect(nil) }
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let point = hold.touchDown
            if let (target, mode) = selectedMode(at: point) {
                begin(mode: mode, target: target, point: point)
            } else {
                let target = target(at: point)
                begin(mode: target == nil ? .create : .move, target: target, point: point)
            }
            track(recognizer)
        case .changed: track(recognizer)
        case .ended: track(recognizer); finish(cancelled: false)
        case .cancelled, .failed: if active != nil { finish(cancelled: true) }
        default: break
        }
    }

    @objc private func panned(_ recognizer: CalendarTimelinePan) {
        switch recognizer.state {
        case .began:
            if let (target, mode) = selectedMode(at: recognizer.touchDown) {
                begin(mode: mode, target: target, point: recognizer.touchDown)
                track(recognizer)
            } else {
                pagePan = true
                panOriginProgress = pageProgress
                pageFeedback.prepare()
            }
        case .changed:
            if pagePan {
                let columnWidth = max(1, (scroll.bounds.width - CalendarTimelineGeometry.gutter) / CGFloat(max(1, configuration.canvas.days.count)))
                let proposed = panOriginProgress - recognizer.translation(in: scroll).x / columnWidth
                pageProgress = boundedProgress(proposed)
                publishProgress()
            } else { track(recognizer) }
        case .ended:
            if pagePan {
                let columnWidth = max(1, (scroll.bounds.width - CalendarTimelineGeometry.gutter) / CGFloat(max(1, configuration.canvas.days.count)))
                // A short pan can end immediately after recognition without a
                // changed callback. Include its final translation before snapping.
                pageProgress = boundedProgress(panOriginProgress - recognizer.translation(in: scroll).x / columnWidth)
                publishProgress()
                let destination = CalendarTimelineGeometry.destination(progress: pageProgress,
                    velocity: recognizer.velocity(in: scroll).x, columnWidth: columnWidth)
                settlePage(direction: destination)
                pagePan = false
            } else { track(recognizer); finish(cancelled: false) }
        case .cancelled, .failed:
            if active != nil { finish(cancelled: true) }
            pagePan = false
            settlePage(direction: 0)
        default: break
        }
    }

    private func boundedProgress(_ proposed: CGFloat) -> CGFloat {
        var destination = Int(proposed.rounded(.awayFromZero))
        while destination != 0 && !configuration.canPage(destination) {
            destination += destination > 0 ? -1 : 1
        }
        return proposed < 0 ? max(proposed, CGFloat(destination)) : min(proposed, CGFloat(destination))
    }

    private func publishProgress() {
        configuration.onPageProgress(pageProgress)
        let day = Int(pageProgress.rounded())
        if day != feedbackDay {
            pageFeedback.selectionChanged()
            pageFeedback.prepare()
            feedbackDay = day
        }
    }

    private func settlePage(direction: Int) {
        settling?.invalidate()
        settleDirection = Int(boundedProgress(CGFloat(direction)))
        settleFrom = pageProgress
        settleTo = CGFloat(settleDirection)
        settleDuration = min(0.70, 0.30 + Double(abs(settleTo - settleFrom)) * 0.065)
        settleStart = CACurrentMediaTime()
        if UIAccessibility.isReduceMotionEnabled { completePage(); return }
        let link = CADisplayLink(target: self, selector: #selector(settleTick(_:)))
        settling = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func settleTick(_ link: CADisplayLink) {
        let fraction = min(1, max(0, (link.targetTimestamp - settleStart) / settleDuration))
        let eased = 1 - pow(1 - fraction, 2)
        pageProgress = settleFrom + (settleTo - settleFrom) * eased
        publishProgress()
        if fraction >= 1 { completePage() }
    }

    private func completePage() {
        settling?.invalidate()
        settling = nil
        if feedbackDay != settleDirection { pageFeedback.selectionChanged() }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if settleDirection != 0 {
                configuration.onPage(settleDirection, false)
            }
            pageProgress = 0
            feedbackDay = 0
            configuration.onPageProgress(0)
        }
    }

    private func begin(mode: CalendarTimelineGestureMode, target: CalendarTimelineTarget?, point: CGPoint) {
        scroll.panGestureRecognizer.isEnabled = false
        active = .init(mode: mode, target: target, origin: point, location: point)
        creationMoved = false
        pageFeedback.prepare()
        if mode != .create { pageFeedback.selectionChanged() }
        configuration.onSelect(target?.id)
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func track(_ recognizer: UIGestureRecognizer) {
        lastWindowPoint = recognizer.location(in: view.window)
        active?.location = recognizer.location(in: host.view)
        if let active, active.mode == .create, !creationMoved,
           hypot(active.location.x - active.origin.x, active.location.y - active.origin.y) > 4 {
            creationMoved = true
            pageFeedback.selectionChanged()
        }
        configuration.onPreview(active)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let active else { return }
        let local = view.convert(lastWindowPoint, from: view.window)
        let margin: CGFloat = 72
        let directionY = local.y < margin ? -1 : (local.y > view.bounds.height - margin ? 1 : 0)
        if directionY != verticalEdgeDirection {
            verticalEdgeDirection = directionY
            verticalEdgeSince = directionY == 0 ? nil : link.timestamp
        }
        let penetration = directionY < 0 ? margin - local.y : local.y - (view.bounds.height - margin)
        let speed = directionY == 0 ? 0 : CGFloat(directionY) * CalendarTimelineGeometry.edgeScrollSpeed(
            penetration: penetration, elapsed: link.timestamp - (verticalEdgeSince ?? link.timestamp))
        if speed != 0 {
            let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
            let next = min(maxY, max(0, scroll.contentOffset.y + speed * CGFloat(link.targetTimestamp - link.timestamp)))
            scroll.contentOffset.y = next
            self.active?.location = host.view.convert(lastWindowPoint, from: view.window)
            configuration.onPreview(self.active)
        }
        guard active.mode == .move || active.mode == .create else { return }
        let direction = CalendarTimelineGeometry.edgeDirection(x: local.x, width: view.bounds.width)
        if direction != edgeDirection { edgeSince = link.timestamp; edgeDirection = direction }
        if direction != 0, let since = edgeSince, link.timestamp - since >= 0.6 {
            edgeSince = link.timestamp
            configuration.onPage(direction, true)
        }
    }

    private func finish(cancelled: Bool) {
        let result = active
        if !cancelled, let result, result.mode != .create { pageFeedback.selectionChanged() }
        stopTracking()
        configuration.onFinish(cancelled ? nil : result)
    }

    func stopTracking() {
        settling?.invalidate()
        settling = nil
        pagePan = false
        pageProgress = 0
        feedbackDay = 0
        displayLink?.invalidate()
        displayLink = nil
        active = nil
        edgeSince = nil
        edgeDirection = 0
        verticalEdgeDirection = 0
        verticalEdgeSince = nil
        scroll.panGestureRecognizer.isEnabled = true
    }
}

final class CalendarTimelinePan: UIPanGestureRecognizer {
    private(set) var touchDown = CGPoint.zero
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { touchDown = touch.location(in: view) }
        super.touchesBegan(touches, with: event)
    }
}

/// Slow drags may recognize as a hold before crossing the pan threshold. Both
/// recognizers must use the same original contact point and selected handle.
final class CalendarTimelineHold: UILongPressGestureRecognizer {
    private(set) var touchDown = CGPoint.zero
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { touchDown = touch.location(in: view) }
        super.touchesBegan(touches, with: event)
    }
}
