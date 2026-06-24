import SwiftUI

enum ExportStatus: Equatable {
    case idle
    case working
    case ready(fileName: String)
    case failure(String)

    var iconName: String {
        switch self {
        case .idle: return "square.and.arrow.up"
        case .working: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle"
        case .failure: return "exclamationmark.triangle"
        }
    }

    var iconColor: Color {
        switch self {
        case .idle, .working: return ListsTokens.accent
        case .ready: return ListsTokens.Hue.green
        case .failure: return ListsTokens.Semantic.danger
        }
    }

    var title: String {
        switch self {
        case .idle: return "Export Library"
        case .working: return "Preparing Export"
        case .ready: return "Export Ready"
        case .failure: return "Export Failed"
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "Creates a ZIP copy of the app-private Lists folder for backup or migration."
        case .working:
            return "Saving recent edits and packaging your local files."
        case .ready(let fileName):
            return "\(fileName) is ready to share."
        case .failure(let message):
            return message
        }
    }
}
