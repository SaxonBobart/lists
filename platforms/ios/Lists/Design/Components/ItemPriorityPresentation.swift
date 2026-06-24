import SwiftUI

extension Item.Priority {
    var displayName: String {
        switch self {
        case .none:   "None"
        case .low:    "Low"
        case .medium: "Medium"
        case .high:   "High"
        }
    }

    var glyph: String {
        switch self {
        case .none:   "exclamationmark.circle"
        case .low:    "exclamationmark"
        case .medium: "exclamationmark.2"
        case .high:   "exclamationmark.3"
        }
    }

    var iconColor: Color {
        switch self {
        case .none:   Color.secondary
        case .low:    .yellow
        case .medium: .orange
        case .high:   .red
        }
    }
}
