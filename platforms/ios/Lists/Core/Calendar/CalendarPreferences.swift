import Foundation
import Observation

enum CalendarViewKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case list
    case day
    case threeDay
    case week
    case month
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list:     return "Agenda"
        case .day:      return "Day"
        case .threeDay: return "3 Days"
        case .week:     return "Week"
        case .month:    return "Month"
        case .year:     return "Year"
        }
    }

    var systemImage: String {
        switch self {
        case .list:     return "list.bullet"
        case .day:      return "calendar.day.timeline.left"
        case .threeDay: return "calendar.day.timeline.leading"
        case .week:     return "calendar"
        case .month:    return "calendar"
        case .year:     return "square.grid.3x3"
        }
    }
}

enum CalendarMonthDensity: Codable, Sendable, CaseIterable, Identifiable, RawRepresentable {
    case compact
    case details

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .compact: return "compact"
        case .details: return "details"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "compact", "stacked": self = .compact
        case "details": self = .details
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown calendar month layout: \(rawValue)"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var label: String {
        switch self {
        case .compact: return "Dots"
        case .details: return "Counts"
        }
    }
}

/// Device-local display policy for every calendar surface. Calendar is a
/// projection over Lists documents, so none of these choices enter Markdown
/// frontmatter or change sync/storage compatibility.
@MainActor
@Observable
final class CalendarPreferences {
    enum RecurrenceVisibility: String, Codable, Sendable, CaseIterable, Identifiable {
        case nextOccurrence
        case visibleRange

        var id: String { rawValue }
        var label: String {
            switch self {
            case .nextOccurrence: return "Next occurrence"
            case .visibleRange:   return "All in visible range"
            }
        }
    }

    private enum Key {
        static let recurrenceVisibility = "lists.calendar.recurrenceVisibility.v1"
        static let showTasks = "lists.calendar.showTasks.v1"
        static let showEvents = "lists.calendar.showEvents.v1"
        static let showHabits = "lists.calendar.showHabits.v1"
        static let showNotes = "lists.calendar.showNotes.v1"
        static let showCompletedItems = "lists.calendar.showCompletedItems.v1"
        static let showCompletedHistory = "lists.calendar.showCompletedHistory.v1"
        static let showMissedHistory = "lists.calendar.showMissedHistory.v1"
        static let showWeekends = "lists.calendar.showWeekends.v1"
        static let showWeekNumbers = "lists.calendar.showWeekNumbers.v1"
        static let hiddenListIds = "lists.calendar.hiddenListIds.v1"
        static let viewKinds = "lists.calendar.viewKinds.v1"
        static let monthDensities = "lists.calendar.monthDensities.v1"
    }

    private let defaults: UserDefaults

    var recurrenceVisibility: RecurrenceVisibility {
        didSet { defaults.set(recurrenceVisibility.rawValue, forKey: Key.recurrenceVisibility) }
    }
    var showTasks: Bool { didSet { defaults.set(showTasks, forKey: Key.showTasks) } }
    var showEvents: Bool { didSet { defaults.set(showEvents, forKey: Key.showEvents) } }
    var showHabits: Bool { didSet { defaults.set(showHabits, forKey: Key.showHabits) } }
    var showNotes: Bool { didSet { defaults.set(showNotes, forKey: Key.showNotes) } }
    var showCompletedItems: Bool {
        didSet { defaults.set(showCompletedItems, forKey: Key.showCompletedItems) }
    }
    var showCompletedHistory: Bool {
        didSet { defaults.set(showCompletedHistory, forKey: Key.showCompletedHistory) }
    }
    var showMissedHistory: Bool {
        didSet { defaults.set(showMissedHistory, forKey: Key.showMissedHistory) }
    }
    var showWeekends: Bool { didSet { defaults.set(showWeekends, forKey: Key.showWeekends) } }
    var showWeekNumbers: Bool {
        didSet { defaults.set(showWeekNumbers, forKey: Key.showWeekNumbers) }
    }
    var hiddenListIds: Set<String> {
        didSet { defaults.set(Array(hiddenListIds).sorted(), forKey: Key.hiddenListIds) }
    }

    private var viewKindsBySurface: [String: CalendarViewKind] {
        didSet { saveViewKinds() }
    }
    private var monthDensityBySurface: [String: CalendarMonthDensity] {
        didSet { saveMonthDensities() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recurrenceVisibility = defaults.string(forKey: Key.recurrenceVisibility)
            .flatMap(RecurrenceVisibility.init(rawValue:))
            ?? .nextOccurrence
        showTasks = Self.bool(defaults, key: Key.showTasks, default: true)
        showEvents = Self.bool(defaults, key: Key.showEvents, default: true)
        showHabits = Self.bool(defaults, key: Key.showHabits, default: false)
        showNotes = Self.bool(defaults, key: Key.showNotes, default: true)
        showCompletedItems = Self.bool(defaults, key: Key.showCompletedItems, default: true)
        showCompletedHistory = Self.bool(defaults, key: Key.showCompletedHistory, default: false)
        showMissedHistory = Self.bool(defaults, key: Key.showMissedHistory, default: false)
        showWeekends = Self.bool(defaults, key: Key.showWeekends, default: true)
        showWeekNumbers = Self.bool(defaults, key: Key.showWeekNumbers, default: false)
        hiddenListIds = Set(defaults.stringArray(forKey: Key.hiddenListIds) ?? [])

        var rawViews = (defaults.dictionary(forKey: Key.viewKinds) as? [String: String]) ?? [:]
        Self.migrateLegacyCalendarSurface(&rawViews)
        viewKindsBySurface = rawViews.compactMapValues(CalendarViewKind.init(rawValue:))
        var rawDensities = (defaults.dictionary(forKey: Key.monthDensities) as? [String: String]) ?? [:]
        Self.migrateLegacyCalendarSurface(&rawDensities)
        monthDensityBySurface = rawDensities.compactMapValues(CalendarMonthDensity.init(rawValue:))
        defaults.set(viewKindsBySurface.mapValues(\.rawValue), forKey: Key.viewKinds)
        defaults.set(monthDensityBySurface.mapValues(\.rawValue), forKey: Key.monthDensities)
    }

    func includes(_ type: Item.ItemType) -> Bool {
        switch type {
        case .task:  return showTasks
        case .event: return showEvents
        case .habit: return showHabits
        case .note:  return showNotes
        }
    }

    func viewKind(for surfaceKey: String, default defaultKind: CalendarViewKind = .month) -> CalendarViewKind {
        viewKindsBySurface[surfaceKey] ?? defaultKind
    }

    func setViewKind(_ kind: CalendarViewKind, for surfaceKey: String) {
        viewKindsBySurface[surfaceKey] = kind
    }

    func monthDensity(
        for surfaceKey: String,
        default defaultDensity: CalendarMonthDensity = .details
    ) -> CalendarMonthDensity {
        monthDensityBySurface[surfaceKey] ?? defaultDensity
    }

    func setMonthDensity(_ density: CalendarMonthDensity, for surfaceKey: String) {
        monthDensityBySurface[surfaceKey] = density
    }

    func setListHidden(_ listId: String, _ hidden: Bool) {
        if hidden {
            hiddenListIds.insert(listId)
        } else {
            hiddenListIds.remove(listId)
        }
    }

    var snapshot: CalendarProjectionPreferences {
        CalendarProjectionPreferences(
            recurrenceVisibility: recurrenceVisibility,
            showTasks: showTasks,
            showEvents: showEvents,
            showHabits: showHabits,
            showNotes: showNotes,
            showCompletedItems: showCompletedItems,
            showCompletedHistory: showCompletedHistory,
            showMissedHistory: showMissedHistory,
            hiddenListIds: hiddenListIds
        )
    }

    private func saveViewKinds() {
        defaults.set(viewKindsBySurface.mapValues(\.rawValue), forKey: Key.viewKinds)
    }

    private func saveMonthDensities() {
        defaults.set(monthDensityBySurface.mapValues(\.rawValue), forKey: Key.monthDensities)
    }

    private static func bool(
        _ defaults: UserDefaults,
        key: String,
        default defaultValue: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }

    private static func migrateLegacyCalendarSurface<Value>(_ values: inout [String: Value]) {
        if values["smart:scheduled"] == nil, let legacy = values["smart:calendar"] {
            values["smart:scheduled"] = legacy
        }
        values.removeValue(forKey: "smart:calendar")
    }
}

struct CalendarProjectionPreferences: Equatable, Sendable {
    let recurrenceVisibility: CalendarPreferences.RecurrenceVisibility
    let showTasks: Bool
    let showEvents: Bool
    let showHabits: Bool
    let showNotes: Bool
    let showCompletedItems: Bool
    let showCompletedHistory: Bool
    let showMissedHistory: Bool
    let hiddenListIds: Set<String>

    func includes(_ type: Item.ItemType) -> Bool {
        switch type {
        case .task:  return showTasks
        case .event: return showEvents
        case .habit: return showHabits
        case .note:  return showNotes
        }
    }
}
