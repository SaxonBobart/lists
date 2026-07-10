import Foundation

enum DocumentMarkdownIndex {
    static func internalLinkURL(for id: UUID) -> URL {
        URL(string: "lists://item/\(id.uuidString)")!
    }

    static func itemId(from url: URL) -> UUID? {
        guard url.scheme == "lists", url.host == "item" else { return nil }
        return UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    static func outline(title: String, body: String) -> [DocumentOutlineEntry] {
        var entries = [
            DocumentOutlineEntry(
                id: "title",
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled",
                level: 1,
                target: .title
            )
        ]
        let ns = body as NSString
        let full = NSRange(location: 0, length: ns.length)
        let regex = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.+)$"#,
                                             options: [.anchorsMatchLines])
        regex.enumerateMatches(in: body, range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let marker = match.range(at: 1)
            let textRange = match.range(at: 2)
            entries.append(DocumentOutlineEntry(
                id: "body-\(match.range.location)",
                title: ns.substring(with: textRange),
                level: marker.length,
                target: .body(match.range)
            ))
        }
        return entries
    }

    static func links(in body: String, items: [Item]) -> [DocumentLinkEntry] {
        let itemTitles = Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, $0.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled")
        })
        let ns = body as NSString
        let full = NSRange(location: 0, length: ns.length)
        var entries: [DocumentLinkEntry] = []

        let markdown = try! NSRegularExpression(pattern: #"(?<!!)\[([^\]\n]+)\]\(([^)\n]+)\)"#)
        markdown.enumerateMatches(in: body, range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let label = ns.substring(with: match.range(at: 1))
            let rawURL = ns.substring(with: match.range(at: 2))
            let destination: DocumentLinkDestination
            let subtitle: String
            if let url = URL(string: rawURL),
               let itemId = itemId(from: url) {
                destination = .internalItem(itemId)
                subtitle = itemTitles[itemId] ?? "Missing document"
            } else if let url = URL(string: rawURL), url.scheme != nil {
                destination = .external(url)
                subtitle = rawURL
            } else {
                destination = .unresolved(rawURL)
                subtitle = "Unresolved"
            }
            entries.append(DocumentLinkEntry(
                id: "md-\(match.range.location)",
                label: label,
                subtitle: subtitle,
                destination: destination,
                range: match.range
            ))
        }

        let wikilink = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+)\]\]"#)
        wikilink.enumerateMatches(in: body, range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let label = ns.substring(with: match.range(at: 1))
            entries.append(DocumentLinkEntry(
                id: "wiki-\(match.range.location)",
                label: label,
                subtitle: "Unresolved",
                destination: .unresolved(label),
                range: match.range
            ))
        }

        return entries.sorted { $0.range.location < $1.range.location }
    }

    static func find(_ query: String, title: String, body: String) -> [DocumentFindResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }
        let pattern = NSRegularExpression.escapedPattern(for: trimmed)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        var results: [DocumentFindResult] = []

        let titleNS = title as NSString
        let titleRange = NSRange(location: 0, length: titleNS.length)
        regex.enumerateMatches(in: title, range: titleRange) { match, _, _ in
            guard let match else { return }
            results.append(DocumentFindResult(
                id: "title-\(match.range.location)",
                excerpt: title.isEmpty ? "Untitled" : title,
                target: .title(match.range)
            ))
        }

        let bodyNS = body as NSString
        let bodyRange = NSRange(location: 0, length: bodyNS.length)
        regex.enumerateMatches(in: body, range: bodyRange) { match, _, _ in
            guard let match else { return }
            let line = bodyNS.lineRange(for: match.range)
            let excerpt = bodyNS.substring(with: line)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(DocumentFindResult(
                id: "body-\(match.range.location)",
                excerpt: excerpt.isEmpty ? "Match" : excerpt,
                target: .body(match.range)
            ))
        }

        return results
    }
}

struct DocumentOutlineEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let level: Int
    let target: DocumentOutlineTarget
}

enum DocumentOutlineTarget: Hashable {
    case title
    case body(NSRange)
}

struct DocumentLinkEntry: Identifiable, Hashable {
    let id: String
    let label: String
    let subtitle: String
    let destination: DocumentLinkDestination
    let range: NSRange
}

enum DocumentLinkDestination: Hashable {
    case internalItem(UUID)
    case external(URL)
    case unresolved(String)
}

struct DocumentFindResult: Identifiable, Hashable {
    let id: String
    let excerpt: String
    let target: DocumentFindTarget
}

enum DocumentFindTarget: Hashable {
    case title(NSRange)
    case body(NSRange)
}
