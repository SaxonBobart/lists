import Foundation
import Observation

/// Persisted UI preferences for the Sidebar:
/// - which auto-lists (Today / Scheduled / Flagged / Urgent / Completed /
///   All) are visible and the order they appear in the colored-tile stack
/// - whether the Tags row sits at the top of My Lists
///
/// Persisted in UserDefaults so it survives relaunch. Auto-lists and Tags
/// are computed views — no on-disk representation in the per-list folder
/// format.
@Observable
final class AutoListPreferences {
    private static let hiddenKey            = "lists.autolists.hidden.v1"
    private static let orderKey             = "lists.autolists.order.v1"
    private static let showTileCountsKey    = "lists.autolists.showTileCounts.v1"
    private static let defaultNewItemTypeKey = "lists.newitem.defaultType.v1"

    /// Default order if the user has never reordered. Tags and Assigned are
    /// pinned tiles too (Assigned is a placeholder).
    static let defaultOrder: [SmartList] = [
        .today, .scheduled, .flagged, .urgent, .completed, .all, .tags, .assigned
    ]

    private let defaults: UserDefaults

    /// Hidden auto-lists. When in this set, they don't appear in the pinned
    /// section. They're still reachable via the Edit Lists screen to unhide.
    var hidden: Set<SmartList> { didSet { saveHidden() } }

    /// Display order. Always contains every SmartList exactly once — new
    /// SmartList cases added in future versions are appended in their default
    /// order on first read.
    var order: [SmartList] { didSet { saveOrder() } }

    /// When true, the item count is shown on each pinned tile. Defaults on.
    var showTileCounts: Bool { didSet { saveShowTileCounts() } }

    /// The item type a single tap on the in-list "+" creates inline. A
    /// long-press always opens the full capture sheet regardless of this.
    /// Defaults to `.task`.
    var defaultNewItemType: Item.ItemType { didSet { saveDefaultNewItemType() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedHidden = (defaults.array(forKey: Self.hiddenKey) as? [String]) ?? []
        self.hidden = Set(storedHidden.compactMap(SmartList.init(rawValue:)))

        let storedOrder = (defaults.array(forKey: Self.orderKey) as? [String]) ?? []
        let parsed = storedOrder.compactMap(SmartList.init(rawValue:))
        let missing = Self.defaultOrder.filter { !parsed.contains($0) }
        self.order = parsed.isEmpty ? Self.defaultOrder : parsed + missing

        // Defaults to true when the user has never set it.
        self.showTileCounts = defaults.object(forKey: Self.showTileCountsKey) == nil
            ? true
            : defaults.bool(forKey: Self.showTileCountsKey)

        self.defaultNewItemType = defaults.string(forKey: Self.defaultNewItemTypeKey)
            .flatMap(Item.ItemType.init(rawValue:)) ?? .task
    }

    /// Visible auto-lists, in user-defined order. The Sidebar renders these.
    var visible: [SmartList] { order.filter { !hidden.contains($0) } }

    func setHidden(_ s: SmartList, _ value: Bool) {
        if value { hidden.insert(s) } else { hidden.remove(s) }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    private func saveHidden() {
        defaults.set(hidden.map(\.rawValue), forKey: Self.hiddenKey)
    }

    private func saveOrder() {
        defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
    }

    private func saveShowTileCounts() {
        defaults.set(showTileCounts, forKey: Self.showTileCountsKey)
    }

    private func saveDefaultNewItemType() {
        defaults.set(defaultNewItemType.rawValue, forKey: Self.defaultNewItemTypeKey)
    }
}
