import Foundation

/// Hashable handle used for sheet(item:) presentation when the FAB drops on
/// a list / section.
struct CaptureTarget: Identifiable, Hashable {
    var id: String { "\(listId)#\(section ?? "")" }
    let listId: String
    let section: String?
}
