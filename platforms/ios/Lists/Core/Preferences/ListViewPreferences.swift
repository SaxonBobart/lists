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
    }

    private static let sortKey          = "lists.listview.sort.v1"
    private static let showCompletedKey = "lists.listview.showCompleted.v1"
    private static let showOverdueKey   = "lists.listview.showOverdue.v1"

    private let defaults: UserDefaults
    private var sortByList: [String: SortMode]            { didSet { saveSort() } }
    private var showCompletedByList: [String: Bool]       { didSet { saveShowCompleted() } }
    private var showOverdueByList: [String: Bool]         { didSet { saveShowOverdue() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let rawSort = (defaults.dictionary(forKey: Self.sortKey) as? [String: String]) ?? [:]
        self.sortByList = rawSort.compactMapValues { SortMode(rawValue: $0) }

        let rawShow = (defaults.dictionary(forKey: Self.showCompletedKey) as? [String: Bool]) ?? [:]
        self.showCompletedByList = rawShow

        let rawOverdue = (defaults.dictionary(forKey: Self.showOverdueKey) as? [String: Bool]) ?? [:]
        self.showOverdueByList = rawOverdue
    }

    func sort(for listId: String) -> SortMode {
        sortByList[listId] ?? .manual
    }

    func setSort(_ mode: SortMode, for listId: String) {
        sortByList[listId] = mode
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

    private func saveSort() {
        let raw = sortByList.mapValues(\.rawValue)
        defaults.set(raw, forKey: Self.sortKey)
    }

    private func saveShowCompleted() {
        defaults.set(showCompletedByList, forKey: Self.showCompletedKey)
    }

    private func saveShowOverdue() {
        defaults.set(showOverdueByList, forKey: Self.showOverdueKey)
    }
}
