import SwiftUI

enum RebuildStatus: Equatable {
    case idle
    case working
    case success(lists: Int, items: Int, issues: Int)
    case failure(String)

    var iconName: String {
        switch self {
        case .idle: return "arrow.clockwise"
        case .working: return "hourglass"
        case .success(_, _, let issues): return issues == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .idle, .working:
            return ListsTokens.Foreground.tertiary
        case .success(_, _, let issues):
            return issues == 0 ? ListsTokens.accent : .orange
        case .failure:
            return ListsTokens.Semantic.danger
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "Rebuild Cache"
        case .working:
            return "Rebuilding"
        case .success:
            return "Library Rebuilt"
        case .failure:
            return "Rebuild Failed"
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "Reload the app's in-memory view from the files stored on this device."
        case .working:
            return "Reading the local Lists folder."
        case let .success(lists, items, issues):
            if issues == 0 {
                return "Reloaded \(lists) lists and \(items) items."
            }
            return "Reloaded \(lists) lists and \(items) items. \(issues) files were moved to a safe place."
        case let .failure(message):
            return message
        }
    }
}
