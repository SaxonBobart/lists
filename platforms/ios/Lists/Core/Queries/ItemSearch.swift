import Foundation

enum ItemSearch {
    enum Scope {
        case fullText(String)
        case itemType(Item.ItemType)
        case hasTags
        case flagged
        case hasLinksOrBacklinks
        case hasTables
        case hasMarkdownTasks
        case hasImagesOrAttachments
    }

    struct ListGroup: Equatable {
        let listName: String
        let items: [Item]
    }

    static func results(
        in items: [Item],
        scope: Scope,
        lingering: Set<UUID> = [],
        lists: [ItemList] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Item] {
        let needle: String?
        switch scope {
        case .fullText(let query):
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { return [] }
            needle = trimmed
        case .itemType,
             .hasTags,
             .flagged,
             .hasLinksOrBacklinks,
             .hasTables,
             .hasMarkdownTasks,
             .hasImagesOrAttachments:
            needle = nil
        }

        let linkDocumentIds = scope.requiresLinkIndex
            ? documentsWithLinksOrBacklinks(in: items, lists: lists)
            : []

        return items.filter { item in
            let isLingering = lingering.contains(item.id)
            let isActive = !item.isComplete(at: now)
                && !item.isRolledOffPastEvent(now: now, calendar: calendar)
            guard item.deletedAt == nil, isLingering || isActive else {
                return false
            }

            switch scope {
            case .fullText:
                guard let needle else { return false }
                if item.title.lowercased().contains(needle) { return true }
                if item.body.lowercased().contains(needle) { return true }
                return item.tags.contains { $0.lowercased().contains(needle) }
            case .itemType(let type):
                return item.type == type
            case .hasTags:
                return !item.tags.isEmpty
            case .flagged:
                return item.flagged
            case .hasLinksOrBacklinks:
                return linkDocumentIds.contains(item.id)
            case .hasTables:
                return !MarkdownTableParser.tables(in: item.body).isEmpty
            case .hasMarkdownTasks:
                return containsMarkdownTask(in: item.body)
            case .hasImagesOrAttachments:
                return containsImageOrAttachment(in: item.body)
            }
        }
    }

    static func groupedByList(_ results: [Item], lists: [ItemList]) -> [ListGroup] {
        let nameById = Dictionary(lists.map { ($0.id, $0.name) }, uniquingKeysWith: { _, new in new })
        let grouped = Dictionary(grouping: results) { item in
            nameById[item.listId] ?? item.listId
        }
        return grouped
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { listName, items in
                ListGroup(
                    listName: listName,
                    items: items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                )
            }
    }

    private static func documentsWithLinksOrBacklinks(
        in items: [Item],
        lists: [ItemList]
    ) -> Set<UUID> {
        var result: Set<UUID> = []
        for source in items where source.deletedAt == nil {
            let links = DocumentMarkdownIndex.links(
                in: source,
                items: items,
                lists: lists
            ).filter { link in
                if case .unresolved(let destination) = link.destination {
                    return !MarkdownAttachmentIndex.isSafeRelativePath(destination)
                }
                return true
            }
            if !links.isEmpty {
                result.insert(source.id)
            }
            for link in links {
                if case .internalItem(let destinationId, heading: _) = link.destination {
                    result.insert(destinationId)
                }
            }
        }
        return result
    }

    private static func containsMarkdownTask(in markdown: String) -> Bool {
        markdownTaskRegex.firstMatch(
            in: markdown,
            range: NSRange(location: 0, length: (markdown as NSString).length)
        ) != nil
    }

    private static func containsImageOrAttachment(in markdown: String) -> Bool {
        if !MarkdownAttachmentIndex.referencedPaths(in: markdown).isEmpty {
            return true
        }
        return markdownImageRegex.firstMatch(
            in: markdown,
            range: NSRange(location: 0, length: (markdown as NSString).length)
        ) != nil
    }

    private static let markdownTaskRegex = try! NSRegularExpression(
        pattern: #"^(?:>+\s*)*\s*[-*+]\s+\[[ xX]\](?:\s|$)"#,
        options: [.anchorsMatchLines]
    )

    private static let markdownImageRegex = try! NSRegularExpression(
        pattern: #"!\[[^\]\n]*\]\([^\)\n]+\)"#
    )
}

private extension ItemSearch.Scope {
    var requiresLinkIndex: Bool {
        if case .hasLinksOrBacklinks = self {
            return true
        }
        return false
    }
}


/// Search is broader than smart-list queries: completed and historical content
/// remains discoverable, while deleted content and deleted lists stay excluded.
enum LibrarySearch {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", items = "Items", lists = "Lists", files = "Files"
        var id: String { rawValue }
    }
    enum Result: Identifiable {
        case item(Item), list(ItemList), file(StandaloneFile)
        var id: String {
            switch self {
            case .item(let item): "item." + item.id.uuidString
            case .list(let list): "list." + list.id
            case .file(let file): "file." + file.id
            }
        }
        var title: String {
            switch self {
            case .item(let item): item.title
            case .list(let list): list.name
            case .file(let file): file.fileName
            }
        }
    }
    static func results(query: String, items: [Item], lists: [ItemList], files: [StandaloneFile],
                        filter: Filter = .all) -> [Result] {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        let activeLists = Set(lists.filter { $0.deletedAt == nil }.map(\.id))
        let definitions = Dictionary(lists.map { list in
            (list.id, Dictionary(list.databaseFields.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
        }, uniquingKeysWith: { first, _ in first })
        func propertyText(_ property: ItemCustomProperty, listID: String) -> [String] {
            let local = definitions[listID] ?? [:]
            var field = property.fieldID.flatMap { local[$0] } ?? DatabaseField(id: property.fieldID ?? property.id, name: property.name)
            if local[field.id] == nil { field.type = property.fieldType ?? "text"; field.options = property.fieldOptions ?? [] }
            return [field.name, property.name, DatabaseSchema.display(property.value, field: field)]
        }
        var matches: [(Result, Int)] = []
        func add(_ result: Result, extra: String = "") {
            let title = normalized(result.title)
            let rank = title == needle ? 0 : title.hasPrefix(needle) ? 1 : title.contains(needle) ? 2 : 3
            if rank < 3 || normalized(extra).contains(needle) { matches.append((result, rank)) }
        }
        if filter == .all || filter == .items {
            for item in items where item.deletedAt == nil && activeLists.contains(item.listId) {
                add(.item(item), extra: ([item.body] + item.tags + item.customProperties.flatMap { propertyText($0, listID: item.listId) }).joined(separator: " "))
            }
        }
        if filter == .all || filter == .lists {
            for list in lists where list.deletedAt == nil { add(.list(list)) }
        }
        if filter == .all || filter == .files {
            for file in files where file.deletedAt == nil && activeLists.contains(file.listID) { add(.file(file)) }
        }
        return matches.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            let order = $0.0.title.localizedStandardCompare($1.0.title)
            return order == .orderedSame ? $0.0.id < $1.0.id : order == .orderedAscending
        }.map { $0.0 }
    }
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
