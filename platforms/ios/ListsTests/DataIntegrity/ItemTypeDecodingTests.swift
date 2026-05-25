import XCTest
@testable import Lists

/// DI-1 (folds in AGENT-1): `type:` decoding must be permissive. An unknown
/// value — a future type, or a corrupted field — must NOT throw. It falls back
/// to `.task` so one stray value can never abort the whole-library load. Known
/// values must still round-trip exactly.
final class ItemTypeDecodingTests: XCTestCase {

    /// A valid frontmatter document with its `type:` value swapped for `typeRaw`.
    /// Encoding a real item first means every other field (esp. the date format)
    /// is genuine, so the test varies only `type`.
    private func frontmatter(typeRaw: String) throws -> String {
        let item = Item(type: .task, title: "Sample", listId: "inbox")
        let encoded = try FrontmatterCodec.encode(item)
        return encoded.replacingOccurrences(of: "type: task", with: "type: \(typeRaw)")
    }

    func testUnknownTypeFallsBackToTask() throws {
        let decoded = try FrontmatterCodec.decode(frontmatter(typeRaw: "question"))
        XCTAssertEqual(decoded.type, .task,
                       "An unknown `type:` must decode as .task, not throw or vanish")
    }

    func testKnownTypesPreservedExactly() throws {
        for type in Item.ItemType.allCases {
            let item = Item(type: type, title: "X", listId: "inbox")
            let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
            XCTAssertEqual(decoded.type, type, "Known type \(type) must round-trip unchanged")
        }
    }
}
