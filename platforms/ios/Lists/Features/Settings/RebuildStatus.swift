import SwiftUI

enum RebuildStatus: Equatable {
    case idle
    case working
    case success(lists: Int, items: Int, issues: Int, pendingRecovery: Bool)
    case failure(String)

    var iconName: String {
        switch self {
        case .idle: return "arrow.clockwise"
        case .working: return "hourglass"
        case .success(_, _, let issues, let pendingRecovery):
            return issues == 0 && !pendingRecovery
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .idle, .working:
            return ListsTokens.Foreground.tertiary
        case .success(_, _, let issues, let pendingRecovery):
            return issues == 0 && !pendingRecovery ? ListsTokens.accent : .orange
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
        case let .success(lists, items, issues, pendingRecovery):
            if pendingRecovery {
                let issueMessage: String
                if issues == 0 {
                    issueMessage = ""
                } else {
                    let noun = issues == 1 ? "issue" : "issues"
                    issueMessage = " Lists found \(issues) additional storage recovery \(noun)."
                }
                return "Reloaded \(lists) lists and \(items) items.\(issueMessage) An interrupted data operation still needs recovery, so affected changes and permanent deletion remain paused."
            } else if issues == 0 {
                return "Reloaded \(lists) lists and \(items) items."
            }
            let noun = issues == 1 ? "issue" : "issues"
            return "Reloaded \(lists) lists and \(items) items. Lists found \(issues) storage recovery \(noun); affected data was left in place or moved aside."
        case let .failure(message):
            return message
        }
    }
}
