import Foundation

enum DocumentMarkdownIndex {
    struct ResolvedInternalLink: Equatable, Sendable {
        let itemId: UUID
        let heading: String?
    }

    static func internalLinkURL(for id: UUID, heading: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "lists"
        components.host = "item"
        components.path = "/\(id.uuidString)"
        components.fragment = heading?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return components.url!
    }

    static func itemId(from url: URL) -> UUID? {
        guard url.scheme == "lists", url.host == "item" else { return nil }
        return UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    static func heading(from url: URL) -> String? {
        guard itemId(from: url) != nil else { return nil }
        return url.fragment.map(fullyDecoded)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func isPotentialInternalDestination(_ destination: String) -> Bool {
        let decoded = destination.removingPercentEncoding ?? destination
        if decoded.hasPrefix("#") { return true }
        let path = decoded.split(separator: "#", maxSplits: 1).first.map(String.init) ?? decoded
        let lowercased = path.lowercased()
        return lowercased.hasSuffix(".md") || lowercased.hasSuffix(".canvas")
    }

    static func portableDestination(from source: Item,
                                    to target: Item,
                                    heading: String? = nil,
                                    lists: [ItemList],
                                    documentFileNames: [UUID: String] = [:]) -> String {
        let sourceDirectory = listPathComponents(for: source.listId, lists: lists)
        let targetPath = portablePathComponents(
            for: target,
            lists: lists,
            documentFileNames: documentFileNames
        )

        let commonCount = zip(sourceDirectory, targetPath).prefix {
            $0.0.caseInsensitiveCompare($0.1) == .orderedSame
        }.count
        let parentSteps = Array(repeating: "..", count: sourceDirectory.count - commonCount)
        let descendant = Array(targetPath.dropFirst(commonCount))
        var path = (parentSteps + descendant)
            .map(percentEncodedPathComponent)
            .joined(separator: "/")
        if path.isEmpty { path = documentFileName(for: target) }
        if let heading = heading?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            path += "#\(percentEncodedFragment(heading))"
        }
        return path
    }

    /// A vault-root-relative destination for formats such as JSON Canvas that
    /// define file nodes independently of a Markdown source document.
    static func portableVaultDestination(
        to target: Item,
        heading: String? = nil,
        lists: [ItemList],
        documentFileNames: [UUID: String] = [:]
    ) -> String {
        var path = portablePathComponents(
            for: target,
            lists: lists,
            documentFileNames: documentFileNames
        )
        .map(percentEncodedPathComponent)
        .joined(separator: "/")
        if let heading = heading?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            path += "#\(percentEncodedFragment(heading))"
        }
        return "/\(path)"
    }

    static func resolveInternalDestination(_ destination: String,
                                           from source: Item,
                                           items: [Item],
                                           lists: [ItemList],
                                           documentFileNames: [UUID: String] = [:]) -> ResolvedInternalLink? {
        if let url = URL(string: destination), let id = itemId(from: url) {
            return ResolvedInternalLink(itemId: id, heading: heading(from: url))
        }

        let pieces = destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = pieces.first.map(String.init) ?? ""
        let heading = pieces.count == 2
            ? fullyDecoded(String(pieces[1]))
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            : nil

        if rawPath.isEmpty {
            return ResolvedInternalLink(itemId: source.id, heading: heading)
        }
        guard isPotentialInternalDestination(destination) else { return nil }

        let decodedPath = rawPath.removingPercentEncoding ?? rawPath
        var components = decodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var normalized = decodedPath.hasPrefix("/")
            ? []
            : listPathComponents(for: source.listId, lists: lists)
        for component in components {
            switch component {
            case ".": continue
            case "..": if normalized.isEmpty == false { normalized.removeLast() }
            default: normalized.append(component)
            }
        }
        components = normalized

        let matches = items.filter { item in
            guard item.deletedAt == nil else { return false }
            let candidate = portablePathComponents(
                for: item,
                lists: lists,
                documentFileNames: documentFileNames
            )
            return candidate.count == components.count
                && zip(candidate, components).allSatisfy {
                    $0.0.caseInsensitiveCompare($0.1) == .orderedSame
                }
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        return ResolvedInternalLink(itemId: match.id, heading: heading)
    }

    static func resolveWikiTarget(_ rawTarget: String,
                                  from source: Item,
                                  items: [Item]) -> ResolvedInternalLink? {
        let targetAndAlias = rawTarget.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let target = String(targetAndAlias[0])
        let targetAndHeading = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let title = String(targetAndHeading[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = targetAndHeading.count == 2
            ? String(targetAndHeading[1]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            : nil
        if title.isEmpty {
            return ResolvedInternalLink(itemId: source.id, heading: heading)
        }
        let matches = items.filter {
            $0.deletedAt == nil
                && $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(title) == .orderedSame
        }
        let preferred = matches.filter { $0.listId == source.listId }
        let resolved = preferred.count == 1 ? preferred.first : (matches.count == 1 ? matches.first : nil)
        return resolved.map { ResolvedInternalLink(itemId: $0.id, heading: heading) }
    }

    static func rewritingPortableDestinations(in currentSource: Item,
                                               oldSource: Item,
                                               oldItems: [Item],
                                               oldLists: [ItemList],
                                               oldDocumentFileNames: [UUID: String] = [:],
                                               newItems: [Item],
                                               newLists: [ItemList],
                                               newDocumentFileNames: [UUID: String] = [:]) -> String {
        var body = currentSource.body
        let links = MarkdownInlineLink.links(in: body)
        for link in links.reversed() {
            guard let resolved = resolveInternalDestination(
                link.destination,
                from: oldSource,
                items: oldItems,
                lists: oldLists,
                documentFileNames: oldDocumentFileNames
            ), let target = newItems.first(where: {
                $0.id == resolved.itemId && $0.deletedAt == nil
            }) else { continue }
            let destination = portableDestination(
                from: currentSource,
                to: target,
                heading: resolved.heading,
                lists: newLists,
                documentFileNames: newDocumentFileNames
            )
            body = (body as NSString).replacingCharacters(
                in: link.destinationRange,
                with: destination
            )
        }
        return body
    }

    /// JSON Canvas file nodes are vault-root-relative rather than relative to
    /// their owning Markdown document. Resolve each card against the old
    /// library shape, then emit its destination against the new one.
    static func rewritingPortableDestinations(
        in cards: [CanvasLinkCard],
        oldSource: Item,
        oldItems: [Item],
        oldLists: [ItemList],
        oldDocumentFileNames: [UUID: String] = [:],
        newItems: [Item],
        newLists: [ItemList],
        newDocumentFileNames: [UUID: String] = [:]
    ) -> [CanvasLinkCard] {
        cards.map { card in
            guard let resolved = resolveInternalDestination(
                card.destination,
                from: oldSource,
                items: oldItems,
                lists: oldLists,
                documentFileNames: oldDocumentFileNames
            ), let target = newItems.first(where: {
                $0.id == resolved.itemId && $0.deletedAt == nil
            }) else { return card }
            var rewritten = card
            rewritten.destination = portableVaultDestination(
                to: target,
                heading: resolved.heading,
                lists: newLists,
                documentFileNames: newDocumentFileNames
            )
            return rewritten
        }
    }

    static func documentFileName(for item: Item) -> String {
        if item.type == .canvas,
           let canvasPath = item.canvasPath,
           let name = canvasPath.split(separator: "/").last {
            return String(name)
        }
        return FileStore.documentBaseFileName(for: item)
    }

    static func portableCanvasDestination(
        from source: Item,
        canvasPath: String,
        lists: [ItemList]
    ) -> String {
        let sourceDirectory = listPathComponents(for: source.listId, lists: lists)
        let targetPath = canvasPath.split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let commonCount = zip(sourceDirectory, targetPath).prefix {
            $0.0.caseInsensitiveCompare($0.1) == .orderedSame
        }.count
        let parentSteps = Array(repeating: "..", count: sourceDirectory.count - commonCount)
        return (parentSteps + Array(targetPath.dropFirst(commonCount)))
            .map(percentEncodedPathComponent)
            .joined(separator: "/")
    }

    private static func portablePathComponents(
        for item: Item,
        lists: [ItemList],
        documentFileNames: [UUID: String]
    ) -> [String] {
        if item.type == .canvas, let canvasPath = item.canvasPath {
            return canvasPath.split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
        }
        return listPathComponents(for: item.listId, lists: lists)
            + [documentFileNames[item.id] ?? documentFileName(for: item)]
    }

    private static func listPathComponents(for listId: String, lists: [ItemList]) -> [String] {
        let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { _, later in later })
        var result: [String] = []
        var current = byId[listId]
        var visited: Set<String> = []
        while let list = current, visited.insert(list.id).inserted {
            result.append(FileStore.sanitize(list.name))
            current = list.parentId.flatMap { byId[$0] }
        }
        return result.reversed()
    }

    private static func percentEncodedPathComponent(_ component: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        // Parentheses are legal URL-path characters but delimit a Markdown
        // inline-link destination, so leaving them literal would truncate a
        // suffixed filename such as `Project (2).md` at the first `)`.
        allowed.remove(charactersIn: "/#?%()")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }

    private static func percentEncodedFragment(_ fragment: String) -> String {
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.remove(charactersIn: "#%")
        return fragment.addingPercentEncoding(withAllowedCharacters: allowed) ?? fragment
    }

    private static func fullyDecoded(_ value: String) -> String {
        var decoded = value
        for _ in 0..<4 {
            guard let next = decoded.removingPercentEncoding, next != decoded else { break }
            decoded = next
        }
        return decoded
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

    static func links(in source: Item,
                      items: [Item],
                      lists: [ItemList],
                      documentFileNames: [UUID: String] = [:]) -> [DocumentLinkEntry] {
        let body = source.body
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
            if let resolved = resolveInternalDestination(
                rawURL,
                from: source,
                items: items,
                lists: lists,
                documentFileNames: documentFileNames
            ) {
                destination = .internalItem(resolved.itemId, heading: resolved.heading)
                let itemTitle = itemTitles[resolved.itemId] ?? "Missing document"
                subtitle = resolved.heading.map { "\(itemTitle) › \($0)" } ?? itemTitle
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
            let rawTarget = ns.substring(with: match.range(at: 1))
            let pieces = rawTarget.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let label = pieces.count == 2 ? String(pieces[1]) : String(pieces[0]).split(separator: "#").first.map(String.init) ?? rawTarget
            let resolved = resolveWikiTarget(rawTarget, from: source, items: items)
            let linkDestination: DocumentLinkDestination
            let subtitle: String
            if let resolved {
                linkDestination = .internalItem(resolved.itemId, heading: resolved.heading)
                let itemTitle = itemTitles[resolved.itemId] ?? "Missing document"
                subtitle = resolved.heading.map { "\(itemTitle) › \($0)" } ?? itemTitle
            } else {
                linkDestination = .unresolved(rawTarget)
                subtitle = "Unresolved"
            }
            entries.append(DocumentLinkEntry(
                id: "wiki-\(match.range.location)",
                label: label,
                subtitle: subtitle,
                destination: linkDestination,
                range: match.range
            ))
        }

        return entries.sorted { $0.range.location < $1.range.location }
    }

    static func backlinks(to itemId: UUID,
                          items: [Item],
                          lists: [ItemList],
                          documentFileNames: [UUID: String] = [:]) -> [DocumentBacklinkEntry] {
        items
            .filter { $0.id != itemId && $0.deletedAt == nil }
            .flatMap { source -> [DocumentBacklinkEntry] in
                links(
                    in: source,
                    items: items,
                    lists: lists,
                    documentFileNames: documentFileNames
                ).compactMap { link in
                    guard case .internalItem(let destinationId, let heading) = link.destination,
                          destinationId == itemId else { return nil }
                    let sourceTitle = source.title
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .nilIfEmpty ?? "Untitled"
                    return DocumentBacklinkEntry(
                        id: "\(source.id.uuidString)-\(link.range.location)",
                        sourceItemId: source.id,
                        sourceTitle: sourceTitle,
                        context: excerpt(around: link.range, in: source.body),
                        heading: heading,
                        range: link.range
                    )
                }
            }
            .sorted {
                if $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedSame {
                    return $0.range.location < $1.range.location
                }
                return $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending
            }
    }

    private static func excerpt(around range: NSRange, in body: String) -> String {
        let ns = body as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else { return "Linked document" }
        return ns.substring(with: ns.lineRange(for: range))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Linked document"
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
    case internalItem(UUID, heading: String?)
    case external(URL)
    case unresolved(String)
}

struct DocumentBacklinkEntry: Identifiable, Hashable {
    let id: String
    let sourceItemId: UUID
    let sourceTitle: String
    let context: String
    let heading: String?
    let range: NSRange
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
