import Foundation
import Observation

enum CalendarViewKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case list
    case day
    case twoDay
    case week
    case month
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list:     return "List"
        case .day:      return "Single Day"
        case .twoDay:   return "Multi Day"
        case .week:     return "Multi Day"
        case .month:    return "Month"
        case .year:     return "Year"
        }
    }

    var parentViewKind: Self? {
        switch self {
        case .year: nil
        case .month: .year
        default: .month
        }
    }

    var systemImage: String {
        switch self {
        case .list:     return "list.dash"
        case .day:      return "calendar.day.timeline.leading"
        case .twoDay, .week: return "rectangle.split.2x1"
        case .month:    return "calendar"
        case .year:     return "square.grid.3x3"
        }
    }

    static func persistedValue(_ rawValue: String) -> Self? {
        rawValue == "threeDay" ? .twoDay : Self(rawValue: rawValue)
    }

    /// Preserve legacy stored choices; window width determines column count.
    var adaptiveValue: Self {
        self == .week ? .twoDay : self
    }

    var compactPhoneValue: Self {
        self == .week ? .twoDay : self
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = Self.persistedValue(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown calendar view: \(rawValue)"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum CalendarOpeningView: String, CaseIterable, Identifiable {
    case year, month, day, twoDay, list

    var id: String { rawValue }
    var viewKind: CalendarViewKind { CalendarViewKind(rawValue: rawValue) ?? .month }
    var label: String { viewKind.label }
}

enum CalendarNavigationLevel: String, Codable, Sendable {
    case year, month, day
}

struct CalendarNavigationState: Codable, Equatable, Sendable {
    enum MonthLayout: String, Codable, Sendable { case list }
    var level: CalendarNavigationLevel = .year
    var monthLayout: MonthLayout = .list
    var dayLayout: CalendarViewKind = .day

    init(legacy: CalendarViewKind = .year) {
        switch legacy {
        case .year: level = .year
        case .month: level = .month
        default: level = .day; dayLayout = legacy.adaptiveValue
        }
    }

    var viewKind: CalendarViewKind {
        switch level {
        case .year: .year
        case .month: .month
        case .day: dayLayout
        }
    }

    mutating func select(_ kind: CalendarViewKind) {
        switch kind {
        case .year: level = .year
        case .month: level = .month
        default: level = .day; dayLayout = kind.adaptiveValue
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
        static let openingViews = "lists.calendar.openingViews.v1"
        static let navigation = "lists.calendar.navigation.v2"
        static let viewKinds = "lists.calendar.viewKinds.v1"
        static let monthDensities = "lists.calendar.monthDensities.v1"
    }

    private let defaults: UserDefaults

    private var openingViewsBySurface: [String: CalendarOpeningView] {
        didSet { defaults.set(openingViewsBySurface.mapValues(\.rawValue), forKey: Key.openingViews) }
    }

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

    private var navigationBySurface: [String: CalendarNavigationState] {
        didSet { if let data = try? JSONEncoder().encode(navigationBySurface) {
            defaults.set(data, forKey: Key.navigation)
        } }
    }
    private var viewKindsBySurface: [String: CalendarViewKind] {
        didSet { saveViewKinds() }
    }
    private var monthDensityBySurface: [String: CalendarMonthDensity] {
        didSet { saveMonthDensities() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var openingViews = (defaults.dictionary(forKey: Key.openingViews) as? [String: String]) ?? [:]
        Self.migrateLegacyCalendarSurface(&openingViews)
        openingViewsBySurface = openingViews.compactMapValues(CalendarOpeningView.init(rawValue:))
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
        viewKindsBySurface = rawViews.compactMapValues(CalendarViewKind.persistedValue)
        var navigation = defaults.data(forKey: Key.navigation)
            .flatMap { try? JSONDecoder().decode([String: CalendarNavigationState].self, from: $0) } ?? [:]
        Self.migrateLegacyCalendarSurface(&navigation)
        for (key, raw) in rawViews where navigation[key] == nil {
            if let legacy = CalendarViewKind.persistedValue(raw) {
                navigation[key] = CalendarNavigationState(legacy: legacy)
            }
        }
        navigationBySurface = navigation
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
        case .habit: return false
        case .note:  return showNotes
        }
    }

    func viewKind(for surfaceKey: String, default defaultKind: CalendarViewKind = .year) -> CalendarViewKind {
        navigationBySurface[surfaceKey]?.viewKind ?? defaultKind
    }

    func setViewKind(_ kind: CalendarViewKind, for surfaceKey: String) {
        var navigation = navigationBySurface[surfaceKey] ?? CalendarNavigationState()
        navigation.select(kind)
        navigationBySurface[surfaceKey] = navigation
        viewKindsBySurface[surfaceKey] = kind
    }

    /// Apply once when a calendar surface is opened, not after sheets or child detail screens.
    func applyOpeningView(for surfaceKey: String) {
        setViewKind(openingView(for: surfaceKey).viewKind, for: surfaceKey)
    }

    func openingView(for surfaceKey: String) -> CalendarOpeningView {
        openingViewsBySurface[surfaceKey] ?? .month
    }

    func setOpeningView(_ view: CalendarOpeningView, for surfaceKey: String) {
        openingViewsBySurface[surfaceKey] = view
    }

    func goToParent(for surfaceKey: String) {
        if let parent = viewKind(for: surfaceKey).parentViewKind {
            setViewKind(parent, for: surfaceKey)
        }
    }

    func dayLayout(for surfaceKey: String) -> CalendarViewKind {
        navigationBySurface[surfaceKey]?.dayLayout ?? .day
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
        case .habit: return false
        case .note:  return showNotes
        }
    }
}
