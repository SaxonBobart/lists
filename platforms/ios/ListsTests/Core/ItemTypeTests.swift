import Foundation
import Testing
@testable import Lists

struct ItemTypeTests {
    @Test func onlyDocumentTypesAreAvailable() {
        #expect(Item.ItemType.allCases == [.task, .note, .event])
        #expect(Item.ItemType.compactMenuOrder == [.event, .note, .task])
    }
}
