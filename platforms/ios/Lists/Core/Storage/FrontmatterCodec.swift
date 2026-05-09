import Foundation
import Yams

/// Encode/decode an `Item` to/from a markdown file with YAML frontmatter.
///
/// On-disk layout per file:
///
///     ---
///     id: 01HX...
///     type: task
///     title: Pay phone bill
///     ...
///     ---
///     <markdown body>
///
public enum FrontmatterCodec {
    public enum Error: Swift.Error, Equatable {
        case missingOpener
        case missingCloser
    }

    public static func encode(_ item: Item) throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = false
        let yaml = try encoder.encode(item)
        let trimmed = yaml.hasSuffix("\n") ? yaml : yaml + "\n"
        let body = item.body.hasSuffix("\n") ? item.body : item.body + (item.body.isEmpty ? "" : "\n")
        return "---\n" + trimmed + "---\n" + body
    }

    public static func decode(_ source: String) throws -> Item {
        let parts = try splitFrontmatter(source)
        var item = try YAMLDecoder().decode(Item.self, from: parts.frontmatter)
        item.body = parts.body
        return item
    }

    private static func splitFrontmatter(_ source: String) throws -> (frontmatter: String, body: String) {
        // Accept files starting with "---\n" or BOM + "---\n"
        let stripped = source.trimmingPrefix("\u{FEFF}")
        guard stripped.hasPrefix("---\n") else { throw Error.missingOpener }
        let after = String(stripped.dropFirst(4))
        guard let closeRange = after.range(of: "\n---\n") else {
            // Allow file ending right at "\n---" (no trailing newline + body)
            if let endRange = after.range(of: "\n---", options: .backwards),
               endRange.upperBound == after.endIndex {
                return (String(after[..<endRange.lowerBound]), "")
            }
            throw Error.missingCloser
        }
        let frontmatter = String(after[..<closeRange.lowerBound])
        let body = String(after[closeRange.upperBound...])
        return (frontmatter, body)
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
