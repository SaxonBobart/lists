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
        var yaml = try encoder.encode(item)
        if !item.frontmatterExtensions.isEmpty, var node = try compose(yaml: yaml) {
            for (key, source) in item.frontmatterExtensions.sorted(by: { $0.key < $1.key }) {
                guard let value = try compose(yaml: source) else { continue }
                if key == "custom_properties" && !item.hasCustomPropertyStorageConflict {
                    guard let current = node[key]?.sequence, let original = value.sequence else { continue }
                    let originals = Dictionary(uniqueKeysWithValues: original.compactMap { entry -> (String, Node)? in
                        guard let id = entry["id"]?.string else { return nil }
                        return (id.lowercased(), entry)
                    })
                    node[key] = Node(current.map { entry in
                        var merged = entry
                        if let id = entry["id"]?.string?.lowercased(), let previous = originals[id]?.mapping {
                            for (name, extra) in previous where !["id", "name", "value", "field_id", "field_type", "field_options"].contains(name.string ?? "") {
                                merged[name] = extra
                            }
                        }
                        return merged
                    })
                } else if node[key] == nil { node[key] = value }
            }
            yaml = try serialize(node: node, allowUnicode: true)
        }
        let trimmed = yaml.hasSuffix("\n") ? yaml : yaml + "\n"
        let body = item.body.hasSuffix("\n") ? item.body : item.body + (item.body.isEmpty ? "" : "\n")
        return "---\n" + trimmed + "---\n" + body
    }


    public static func decode(_ source: String) throws -> Item {
        let parts = try splitFrontmatter(source)
        var item = try YAMLDecoder().decode(Item.self, from: parts.frontmatter)
        item.body = parts.body
        if let mapping = try compose(yaml: parts.frontmatter)?.mapping {
            for (key, value) in mapping {
                guard let name = key.string else { continue }
                let hasCustomExtensions = name == "custom_properties" && (value.sequence?.contains { entry in
                    entry.mapping?.contains { !["id", "name", "value", "field_id", "field_type", "field_options"].contains($0.key.string ?? "") } == true
                } ?? false)
                guard !Item.frontmatterKeyNames.contains(name) || (name == "custom_properties" && item.hasCustomPropertyStorageConflict) || hasCustomExtensions else { continue }
                item.frontmatterExtensions[name] = try serialize(node: value, allowUnicode: true)
            }
        }
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
