import Foundation
import Testing
@testable import Lists

struct ItemTypePolicyTests {
    @Test func onlyDocumentTypesAreAvailable() {
        #expect(Item.ItemType.allCases == [.task, .note, .event])
        #expect(ItemTypePolicy().quickCaptureTypes == [.task, .note, .event])
        #expect(!ItemTypePolicy().isAvailable(.habit))
        #expect(ItemTypePolicy().effectiveDefaultType(.habit) == .task)
    }
    @Test func retiredHabitDocumentsAreIsolated() throws {
        let source = try FrontmatterCodec.encode(Item(type: .habit, title: "Legacy", listId: "inbox"))
        #expect(throws: (any Error).self) { try FrontmatterCodec.decode(source) }
        let task = try FrontmatterCodec.encode(Item(type: .task, title: "Task", listId: "inbox"))
        #expect(try FrontmatterCodec.decode(task).type == .task)
    }
}
