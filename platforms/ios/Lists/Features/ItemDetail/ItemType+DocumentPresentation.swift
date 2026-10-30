extension Item.ItemType {
    static let compactMenuOrder: [Self] = [.event, .note, .task]

    var documentDisplayName: String {
        switch self {
        case .task:  return "Task"
        case .note:  return "Note"
        case .event: return "Event"
        }
    }

    var documentGlyph: String {
        switch self {
        case .task:  return "circle"
        case .note:  return "text.document"
        case .event: return "calendar"
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .task:  return "New Task"
        case .note:  return "New Note"
        case .event: return "New Event"
        }
    }
}
