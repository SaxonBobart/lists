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
        itemTypePolicy: ItemTypePolicy = .allEnabled,
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
            guard item.isAvailable(in: itemTypePolicy) else { return false }

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
