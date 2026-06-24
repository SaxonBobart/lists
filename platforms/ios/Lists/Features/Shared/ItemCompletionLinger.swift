import Foundation

/// Shared row-completion transition for list and smart-list surfaces.
@MainActor
enum ItemCompletionLinger {
    static func toggle(
        _ item: Item,
        store: ItemStore,
        showCompleted: Bool,
        lingeringIds: inout Set<UUID>,
        startLinger: (UUID) -> Void
    ) {
        let willComplete = !item.done
        Task { try? await store.toggleDone(item.id) }
        guard willComplete, !showCompleted else {
            lingeringIds.remove(item.id)
            return
        }
        startLinger(item.id)
    }

    static func incrementHabit(
        _ item: Item,
        store: ItemStore,
        showCompleted: Bool,
        startLinger: (UUID) -> Void
    ) {
        let live = store.item(item.id) ?? item
        let now = Date.now
        let key = HabitCycle.key(for: (live.frequency ?? .daily).normalizedForHabit, on: now)
        let current = live.completionLog[key] ?? 0
        let willComplete = current + 1 >= live.goalPerCycle
        Task { try? await store.incrementHabit(item.id, now: now) }
        guard willComplete, !showCompleted else { return }
        startLinger(item.id)
    }
}
