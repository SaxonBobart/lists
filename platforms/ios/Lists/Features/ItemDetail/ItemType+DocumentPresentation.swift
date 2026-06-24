extension Item.ItemType {
    var documentDisplayName: String {
        switch self {
        case .task:  return "Task"
        case .note:  return "Note"
        case .habit: return "Habit"
        case .event: return "Event"
        }
    }

    var documentGlyph: String {
        switch self {
        case .task:  return "circle"
        case .note:  return "text.document"
        case .habit: return "checkmark.arrow.trianglehead.clockwise"
        case .event: return "calendar"
        }
    }
}
