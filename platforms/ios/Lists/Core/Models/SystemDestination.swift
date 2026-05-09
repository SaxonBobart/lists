import Foundation

/// Sidebar system rows that need a NavigationStack value (Tags, Recently
/// Deleted). Smart lists and user lists have their own value types — this
/// covers everything else.
public enum SystemDestination: String, Hashable, CaseIterable, Sendable {
    case tags
    case recentlyDeleted
}
