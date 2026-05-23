import Foundation
import Observation

/// Persisted UI preferences for a single user list:
/// - Sort mode (Manual / Due date / Alphabetical / Date added / Priority)
/// - "Show completed" toggle (off by default)
///
/// Stored in UserDefaults, keyed by list id. Sort + layout will eventually
/// mirror to `_list.yaml` (spec §5.12), but for now this UI store is
/// device-local — same pattern as `AutoListPreferences`.
@Observable
final class ListViewPreferences {
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

    private static let sortKey          = "lists.listview.sort.v1"
    private static let sortDirKey       = "lists.listview.sortDirection.v1"
    private static let showCompletedKey = "lists.listview.showCompleted.v1"
    private static let showOverdueKey   = "lists.listview.showOverdue.v1"
    private static let subListsExpandedKey = "lists.listview.subListsExpanded.v1"
    private static let sectionExpandedKey  = "lists.listview.sectionExpanded.v1"
    private static let itemExpandedKey     = "lists.listview.itemExpanded.v1"

    private let defaults: UserDefaults
    private var sortByList: [String: SortMode]            { didSet { saveSort() } }
    private var sortDirByList: [String: SortDirection]    { didSet { saveSortDir() } }
    private var showCompletedByList: [String: Bool]       { didSet { saveShowCompleted() } }
    private var showOverdueByList: [String: Bool]         { didSet { saveShowOverdue() } }
    private var subListsExpandedByList: [String: Bool]    { didSet { saveSubListsExpanded() } }
    /// `[listId: [sectionId: expanded]]`. Default for a missing key is `true`
    /// (sections start expanded).
    private var sectionExpandedByList: [String: [String: Bool]] { didSet { saveSectionExpanded() } }
    /// `[listId: [itemId: expanded]]`. Default for a missing key is `true`
    /// (items with sub-items start expanded).
    private var itemExpandedByList: [String: [String: Bool]] { didSet { saveItemExpanded() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let rawSort = (defaults.dictionary(forKey: Self.sortKey) as? [String: String]) ?? [:]
        self.sortByList = rawSort.compactMapValues { SortMode(rawValue: $0) }

        let rawSortDir = (defaults.dictionary(forKey: Self.sortDirKey) as? [String: String]) ?? [:]
        self.sortDirByList = rawSortDir.compactMapValues { SortDirection(rawValue: $0) }

        let rawShow = (defaults.dictionary(forKey: Self.showCompletedKey) as? [String: Bool]) ?? [:]
        self.showCompletedByList = rawShow

        let rawOverdue = (defaults.dictionary(forKey: Self.showOverdueKey) as? [String: Bool]) ?? [:]
        self.showOverdueByList = rawOverdue

        let rawSubLists = (defaults.dictionary(forKey: Self.subListsExpandedKey) as? [String: Bool]) ?? [:]
        self.subListsExpandedByList = rawSubLists

        let rawSection = (defaults.dictionary(forKey: Self.sectionExpandedKey) as? [String: [String: Bool]]) ?? [:]
        self.sectionExpandedByList = rawSection

        let rawItem = (defaults.dictionary(forKey: Self.itemExpandedKey) as? [String: [String: Bool]]) ?? [:]
        self.itemExpandedByList = rawItem
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
    /// is `true` — Saxon wants users to opt out, not opt in.
    func showOverdue(for listId: String) -> Bool {
        showOverdueByList[listId] ?? true
    }

    func setShowOverdue(_ value: Bool, for listId: String) {
        showOverdueByList[listId] = value
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
}
