import SwiftUI

/// Shared row-completion transition for list and smart-list surfaces.
@MainActor
enum ItemCompletionLinger {
    enum Transition: Equatable {
        case start
        case remove
        case none
    }

    static func toggle(
        _ item: Item,
        store: ItemStore,
        showCompleted: Bool
    ) async throws -> Transition {
        let willComplete = !item.done
        try await store.toggleDone(item.id)
        guard willComplete else { return .remove }
        return showCompleted ? .remove : .start
    }

    static func incrementHabit(
        _ item: Item,
        store: ItemStore,
        showCompleted: Bool,
        now: Date = .now
    ) async throws -> Transition {
        let live = store.item(item.id) ?? item
        let key = HabitCycle.key(for: (live.frequency ?? .daily).normalizedForHabit, on: now)
        let current = live.completionLog[key] ?? 0
        let willComplete = current + 1 >= live.goalPerCycle
        try await store.incrementHabit(item.id, now: now)
        return willComplete && !showCompleted ? .start : .none
    }

    static func apply(
        _ transition: Transition,
        itemID: UUID,
        lingeringIds: Binding<Set<UUID>>,
        startLinger: (UUID) -> Void
    ) {
        switch transition {
        case .start:
            startLinger(itemID)
        case .remove:
            lingeringIds.wrappedValue.remove(itemID)
        case .none:
            break
        }
    }

    static func toggle(
        _ item: Item,
        store: ItemStore,
        showCompleted: Bool,
        lingeringIds: Binding<Set<UUID>>,
        startLinger: @escaping (UUID) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        Task {
            do {
                let transition = try await toggle(
                    item,
                    store: store,
                    showCompleted: showCompleted
                )
                apply(
                    transition,
                    itemID: item.id,
                    lingeringIds: lingeringIds,
                    startLinger: startLinger
                )
            } catch {
                onFailure(error.localizedDescription)
            }
        }
    }

    static func incrementHabit(
        _ item: Item,
        store: ItemStore,
        showCompleted: Bool,
        lingeringIds: Binding<Set<UUID>>,
        startLinger: @escaping (UUID) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        Task {
            do {
                let transition = try await incrementHabit(
                    item,
                    store: store,
                    showCompleted: showCompleted
                )
                apply(
                    transition,
                    itemID: item.id,
                    lingeringIds: lingeringIds,
                    startLinger: startLinger
                )
            } catch {
                onFailure(error.localizedDescription)
            }
        }
    }
}

extension View {
    /// Completion controls appear on five different list surfaces. Keep their
    /// persistence failure treatment identical instead of letting a failed tap
    /// look like a successful completion on some screens and disappear on others.
    func itemMutationErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Couldn’t Update Item",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented { message.wrappedValue = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("item.mutation.error.dismiss")
        } message: {
            if let detail = message.wrappedValue { Text(detail) }
        }
    }
}
