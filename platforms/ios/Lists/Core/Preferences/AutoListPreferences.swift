import Foundation
import Observation

/// Persisted UI preferences for the Sidebar:
/// - which auto-lists (Today / Calendar / Scheduled / Flagged / Alarms /
///   Completed / All / Tags) are visible and their tile order
/// - whether counts appear on those pinned tiles
///
/// Persisted in UserDefaults so it survives relaunch. Auto-lists and Tags
/// are computed views — no on-disk representation in the per-list folder
/// format.
@MainActor
@Observable
final class AutoListPreferences {
    private static let hiddenKey            = "lists.autolists.hidden.v1"
    private static let orderKey             = "lists.autolists.order.v1"
    private static let showTileCountsKey    = "lists.autolists.showTileCounts.v1"
    private static let defaultNewItemTypeKey = "lists.newitem.defaultType.v1"
    private static let defaultCaptureListKey = "lists.newitem.defaultList.v1"

    /// Smart lists currently shipped in the sidebar.
    static let activeSmartLists: [SmartList] = [
        .today, .calendar, .scheduled, .flagged, .alarms, .completed, .all, .tags
    ]

    /// Default order if the user has never reordered. Tags is a pinned tile too.
    static let defaultOrder: [SmartList] = [
        .today, .calendar, .scheduled, .flagged, .alarms, .completed, .all, .tags
    ]

    private let defaults: UserDefaults

    /// Hidden auto-lists. When in this set, they don't appear in the pinned
    /// section. They're still reachable via the Edit Lists screen to unhide.
    var hidden: Set<SmartList> { didSet { saveHidden() } }

    /// Display order. Always contains every SmartList exactly once; new cases
    /// introduced by later builds are appended in their default order on read.
    var order: [SmartList] { didSet { saveOrder() } }

    /// When true, the item count is shown on each pinned tile. Defaults on.
    var showTileCounts: Bool { didSet { saveShowTileCounts() } }

    /// The item type a single tap on the in-list "+" creates inline. A
    /// long-press always opens the full capture sheet regardless of this.
    /// Defaults to `.task`.
    var defaultNewItemType: Item.ItemType { didSet { saveDefaultNewItemType() } }

    /// The user-list target for the overview "+". Defaults to Inbox.
    var defaultCaptureListId: String { didSet { saveDefaultCaptureList() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedHidden = (defaults.array(forKey: Self.hiddenKey) as? [String]) ?? []
        self.hidden = Set(storedHidden.compactMap(SmartList.persistedValue(_:)))
            .intersection(Self.activeSmartLists)

        let storedOrder = (defaults.array(forKey: Self.orderKey) as? [String]) ?? []
        // De-duplicate while preserving first-seen order so a corrupt payload
        // cannot make a SmartList appear twice in the sidebar.
        var seen = Set<SmartList>()
        let active = Set(Self.activeSmartLists)
        let parsed = storedOrder
            .compactMap(SmartList.persistedValue(_:))
            .filter { active.contains($0) && seen.insert($0).inserted }
        let missing = Self.defaultOrder.filter { !seen.contains($0) }
        self.order = parsed.isEmpty ? Self.defaultOrder : parsed + missing

        // Defaults to true when the user has never set it.
        self.showTileCounts = defaults.object(forKey: Self.showTileCountsKey) == nil
            ? true
            : defaults.bool(forKey: Self.showTileCountsKey)

        self.defaultNewItemType = defaults.string(forKey: Self.defaultNewItemTypeKey)
            .flatMap(Item.ItemType.init(rawValue:)) ?? .task

        self.defaultCaptureListId = defaults.string(forKey: Self.defaultCaptureListKey)
            ?? ItemList.inboxId
    }

    /// Visible auto-lists, in user-defined order. The Sidebar renders these.
    var visible: [SmartList] {
        order.filter { Self.activeSmartLists.contains($0) && !hidden.contains($0) }
    }

    func setHidden(_ s: SmartList, _ value: Bool) {
        if value { hidden.insert(s) } else { hidden.remove(s) }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    func resolvedDefaultCaptureList(in lists: [ItemList]) -> ItemList? {
        let activeLists = lists.filter { $0.deletedAt == nil }
        if let selected = activeLists.first(where: { $0.id == defaultCaptureListId }) {
            return selected
        }
        if let inbox = activeLists.first(where: { $0.id == ItemList.inboxId }) {
            return inbox
        }
        return activeLists.sorted { $0.position < $1.position }.first
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

    private func saveDefaultCaptureList() {
        defaults.set(defaultCaptureListId, forKey: Self.defaultCaptureListKey)
    }
}
