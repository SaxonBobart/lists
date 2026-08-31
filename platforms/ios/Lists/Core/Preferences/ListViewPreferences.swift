import Foundation
import Observation

/// Persisted UI preferences for a single user list:
/// - View mode (List / Columns / Calendar)
/// - Sort mode (Manual / Due date / Alphabetical / Date added / Priority)
/// - "Show completed" toggle (off by default)
/// - Date-query visibility such as overdue and past event roll-off
/// - Expanded/collapsed state for sublists, sections, and item subtrees
///
/// Stored in UserDefaults, keyed by list id. These are device-local UI choices;
/// the plain-text list files remain the source of truth for product data.
@MainActor
@Observable
final class ListViewPreferences {
    enum ViewMode: String, Codable, Sendable, CaseIterable {
        case list
        case columns
        case calendar

        var label: String {
            switch self {
            case .list:     return "List"
            case .columns:  return "Columns"
            case .calendar: return "Calendar"
            }
        }

        var systemImage: String {
            switch self {
            case .list:     return "list.bullet"
            case .columns:  return "rectangle.split.3x1"
            case .calendar: return "calendar"
            }
        }

        /// User-owned lists can become Kanban boards when they have real
        /// sections. Query surfaces never expose Columns: their visual
        /// groupings are projections, not durable list sections.
        static func availableForUserList(hasSections: Bool) -> [Self] {
            hasSections ? [.list, .columns, .calendar] : [.list, .calendar]
        }

        static let queryModes: [Self] = [.list, .calendar]
    }

    enum SortDirection: String, Codable, Sendable, CaseIterable {
        case ascending, descending
        var label: String { self == .ascending ? "Ascending" : "Descending" }
        var systemImage: String { self == .ascending ? "chevron.up" : "chevron.down" }
    }

    enum SortMode: String, Codable, Sendable, CaseIterable {
        case manual, due, alphabetical, created, priority

        var label: String {
            switch self {
            case .manual:       return "Manual"
            case .due:          return "Due Date"
            case .alphabetical: return "Title"
            case .created:      return "Date Added"
            case .priority:     return "Priority"
            }
        }

        var systemImage: String {
            switch self {
            case .manual:       return "hand.point.up.left"
            case .due:          return "calendar"
            case .alphabetical: return "textformat"
            case .created:      return "clock"
            case .priority:     return "exclamationmark.circle"
            }
        }

        /// Context-aware direction labels — e.g. for Deadline we show
        /// "Earliest First" / "Latest First" rather than the generic
        /// Ascending / Descending pair.
        func directionLabel(_ direction: SortDirection) -> String {
            switch self {
            case .manual:
                return direction == .ascending ? "Ascending" : "Descending"
            case .due:
                return direction == .ascending ? "Earliest First" : "Latest First"
            case .created:
                return direction == .ascending ? "Oldest First" : "Latest First"
            case .priority:
                return direction == .ascending ? "Highest First" : "Lowest First"
            case .alphabetical:
                return direction == .ascending ? "Ascending" : "Descending"
            }
        }
    }

    private static let viewModeKey      = "lists.listview.viewMode.v1"
    private static let sortKey          = "lists.listview.sort.v1"
    private static let sortDirKey       = "lists.listview.sortDirection.v1"
    private static let showCompletedKey = "lists.listview.showCompleted.v1"
    private static let showOverdueKey   = "lists.listview.showOverdue.v1"
    private static let showPastEventsKey = "lists.listview.showPastEvents.v1"
    private static let subListsExpandedKey = "lists.listview.subListsExpanded.v1"
    private static let sectionExpandedKey  = "lists.listview.sectionExpanded.v1"
    private static let itemExpandedKey     = "lists.listview.itemExpanded.v1"

    private let defaults: UserDefaults
    private var viewModeByList: [String: ViewMode]        { didSet { saveViewMode() } }
    private var sortByList: [String: SortMode]            { didSet { saveSort() } }
    private var sortDirByList: [String: SortDirection]    { didSet { saveSortDir() } }
    private var showCompletedByList: [String: Bool]       { didSet { saveShowCompleted() } }
    private var showOverdueByList: [String: Bool]         { didSet { saveShowOverdue() } }
    private var showPastEventsByList: [String: Bool]      { didSet { saveShowPastEvents() } }
    private var subListsExpandedByList: [String: Bool]    { didSet { saveSubListsExpanded() } }
    /// `[listId: [sectionId: expanded]]`. Default for a missing key is `true`
    /// (sections start expanded).
    private var sectionExpandedByList: [String: [String: Bool]] { didSet { saveSectionExpanded() } }
    /// `[listId: [itemId: expanded]]`. Default for a missing key is `true`
    /// (items with sub-items start expanded).
    private var itemExpandedByList: [String: [String: Bool]] { didSet { saveItemExpanded() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        var rawViewMode = (defaults.dictionary(forKey: Self.viewModeKey) as? [String: String]) ?? [:]
        Self.migrateLegacyCalendarSurface(&rawViewMode)
        self.viewModeByList = rawViewMode.compactMapValues { ViewMode(rawValue: $0) }

        var rawSort = (defaults.dictionary(forKey: Self.sortKey) as? [String: String]) ?? [:]
        Self.migrateLegacyCalendarSurface(&rawSort)
        self.sortByList = rawSort.compactMapValues { SortMode(rawValue: $0) }

        var rawSortDir = (defaults.dictionary(forKey: Self.sortDirKey) as? [String: String]) ?? [:]
        Self.migrateLegacyCalendarSurface(&rawSortDir)
        self.sortDirByList = rawSortDir.compactMapValues { SortDirection(rawValue: $0) }

        var rawShow = (defaults.dictionary(forKey: Self.showCompletedKey) as? [String: Bool]) ?? [:]
        Self.migrateLegacyCalendarSurface(&rawShow)
        self.showCompletedByList = rawShow

        var rawOverdue = (defaults.dictionary(forKey: Self.showOverdueKey) as? [String: Bool]) ?? [:]
        Self.migrateLegacyCalendarSurface(&rawOverdue)
        self.showOverdueByList = rawOverdue

        var rawPastEvents = (defaults.dictionary(forKey: Self.showPastEventsKey) as? [String: Bool]) ?? [:]
        Self.migrateLegacyCalendarSurface(&rawPastEvents)
        self.showPastEventsByList = rawPastEvents

        let rawSubLists = (defaults.dictionary(forKey: Self.subListsExpandedKey) as? [String: Bool]) ?? [:]
        self.subListsExpandedByList = rawSubLists

        let rawSection = (defaults.dictionary(forKey: Self.sectionExpandedKey) as? [String: [String: Bool]]) ?? [:]
        self.sectionExpandedByList = rawSection

        let rawItem = (defaults.dictionary(forKey: Self.itemExpandedKey) as? [String: [String: Bool]]) ?? [:]
        self.itemExpandedByList = rawItem

        defaults.set(rawViewMode, forKey: Self.viewModeKey)
        defaults.set(rawSort, forKey: Self.sortKey)
        defaults.set(rawSortDir, forKey: Self.sortDirKey)
        defaults.set(rawShow, forKey: Self.showCompletedKey)
        defaults.set(rawOverdue, forKey: Self.showOverdueKey)
        defaults.set(rawPastEvents, forKey: Self.showPastEventsKey)
    }

    private static func migrateLegacyCalendarSurface<Value>(_ values: inout [String: Value]) {
        if values["smart:scheduled"] == nil, let legacy = values["smart:calendar"] {
            values["smart:scheduled"] = legacy
        }
        values.removeValue(forKey: "smart:calendar")
    }

    func viewMode(
        for listId: String,
        default defaultMode: ViewMode = .list
    ) -> ViewMode {
        viewModeByList[listId] ?? defaultMode
    }

    func setViewMode(_ mode: ViewMode, for listId: String) {
        viewModeByList[listId] = mode
    }

    func sort(for listId: String) -> SortMode {
        sortByList[listId] ?? .manual
    }

    func setSort(_ mode: SortMode, for listId: String) {
        sortByList[listId] = mode
    }

    func sortDirection(for listId: String) -> SortDirection {
        sortDirByList[listId] ?? .ascending
    }

    func setSortDirection(_ dir: SortDirection, for listId: String) {
        sortDirByList[listId] = dir
    }

    func showCompleted(for listId: String) -> Bool {
        showCompletedByList[listId] ?? false
    }

    func setShowCompleted(_ value: Bool, for listId: String) {
        showCompletedByList[listId] = value
    }

    /// Whether overdue items appear in views that section by date. Default
    /// is `true` — users opt out rather than opting in.
    func showOverdue(for listId: String) -> Bool {
        showOverdueByList[listId] ?? true
    }

    func setShowOverdue(_ value: Bool, for listId: String) {
        showOverdueByList[listId] = value
    }

    /// Whether *past* calendar events (non-completable events that ended before
    /// today) appear in list views. Default `false` — they roll off the list at
    /// the end of their day unless the user opts to surface them here. See
    /// `Item.isRolledOffPastEvent`.
    func showPastEvents(for listId: String) -> Bool {
        showPastEventsByList[listId] ?? false
    }

    func setShowPastEvents(_ value: Bool, for listId: String) {
        showPastEventsByList[listId] = value
    }

    /// Whether the "Sub-Lists" section is expanded in a given list's detail
    /// view. Default `true` — sub-lists are visible by default.
    func subListsExpanded(for listId: String) -> Bool {
        subListsExpandedByList[listId] ?? true
    }

    func setSubListsExpanded(_ value: Bool, for listId: String) {
        subListsExpandedByList[listId] = value
    }

    private func saveSubListsExpanded() {
        defaults.set(subListsExpandedByList, forKey: Self.subListsExpandedKey)
    }

    /// Whether a given section is expanded inside a given list. Defaults to
    /// `true` — sections start expanded.
    func sectionExpanded(_ sectionId: String, in listId: String) -> Bool {
        sectionExpandedByList[listId]?[sectionId] ?? true
    }

    func setSectionExpanded(_ expanded: Bool, sectionId: String, in listId: String) {
        var map = sectionExpandedByList[listId] ?? [:]
        map[sectionId] = expanded
        sectionExpandedByList[listId] = map
    }

    private func saveSectionExpanded() {
        defaults.set(sectionExpandedByList, forKey: Self.sectionExpandedKey)
    }

    /// Whether a given item's sub-items are shown inside a given list.
    /// Defaults to `true` — items with children start expanded.
    func itemExpanded(_ itemId: String, in listId: String) -> Bool {
        itemExpandedByList[listId]?[itemId] ?? true
    }

    func setItemExpanded(_ expanded: Bool, itemId: String, in listId: String) {
        var map = itemExpandedByList[listId] ?? [:]
        map[itemId] = expanded
        itemExpandedByList[listId] = map
    }

    private func saveItemExpanded() {
        defaults.set(itemExpandedByList, forKey: Self.itemExpandedKey)
    }

    private func saveSort() {
        let raw = sortByList.mapValues(\.rawValue)
        defaults.set(raw, forKey: Self.sortKey)
    }

    private func saveViewMode() {
        let raw = viewModeByList.mapValues(\.rawValue)
        defaults.set(raw, forKey: Self.viewModeKey)
    }

    private func saveSortDir() {
        let raw = sortDirByList.mapValues(\.rawValue)
        defaults.set(raw, forKey: Self.sortDirKey)
    }

    private func saveShowCompleted() {
        defaults.set(showCompletedByList, forKey: Self.showCompletedKey)
    }

    private func saveShowOverdue() {
        defaults.set(showOverdueByList, forKey: Self.showOverdueKey)
    }

    private func saveShowPastEvents() {
        defaults.set(showPastEventsByList, forKey: Self.showPastEventsKey)
    }
}
