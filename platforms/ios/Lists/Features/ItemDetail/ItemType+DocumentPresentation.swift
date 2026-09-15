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

    var descriptionPlaceholder: String {
        switch self {
        case .task, .habit: return "Describe a task"
        case .note: return "Describe a note"
        case .event: return "Describe an event"
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .task:  return "New Task"
        case .note:  return "New Note"
        case .habit: return "New Habit"
        case .event: return "New Event"
        }
    }
}
