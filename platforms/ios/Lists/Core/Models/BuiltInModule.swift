import Foundation

/// First-party feature modules that ship as part of Lists.
///
/// This is deliberately not an external plugin API. It gives app surfaces a
/// shared product vocabulary for built-in modules while persistence stays in
/// the normal local-first `Item` model.
enum BuiltInModule: String, CaseIterable, Identifiable, Sendable {
    case habits

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .habits: return "Habits"
        }
    }

    var statusLabel: String {
        switch self {
        case .habits: return "Built-in"
        }
    }
}
