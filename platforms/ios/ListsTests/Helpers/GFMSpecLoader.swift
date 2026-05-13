import Foundation

/// One entry from the official CommonMark / GFM spec.json corpus.
struct GFMSpecFixture: Decodable, Hashable, Sendable {
    let markdown: String
    let html: String
    let example: Int
    let section: String

    enum CodingKeys: String, CodingKey {
        case markdown
        case html
        case example
        case section
    }
}

/// Loads the vendored spec fixtures from
/// `shared/format/markdown-fixtures/`. The path is resolved relative
/// to the source tree via `#filePath` so the test target doesn't
/// need a custom resource pipeline.
enum GFMSpecLoader {
    static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // .../ListsTests/Helpers
            .deletingLastPathComponent()  // .../ListsTests
            .deletingLastPathComponent()  // .../ios
            .deletingLastPathComponent()  // .../platforms
            .deletingLastPathComponent()  // .../lists (repo root)
    }()

    static func load(_ filename: String) throws -> [GFMSpecFixture] {
        let url = repoRoot
            .appendingPathComponent("shared/format/markdown-fixtures/\(filename)")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([GFMSpecFixture].self, from: data)
    }

    static func loadIfPresent(_ filename: String) -> [GFMSpecFixture] {
        (try? load(filename)) ?? []
    }
}
