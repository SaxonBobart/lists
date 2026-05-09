import Foundation

/// Hashable value used by NavigationStack for routing into ThreadView from
/// inside ItemDetailSheet (or anywhere else that needs to push the thread).
public struct ThreadDestination: Hashable, Sendable {
    public let rootId: UUID

    public init(rootId: UUID) {
        self.rootId = rootId
    }
}
