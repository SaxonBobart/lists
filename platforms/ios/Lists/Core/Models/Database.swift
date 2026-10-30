import Foundation

public struct DatabaseOption: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

/// Definitions belong to a list. Values retain the existing portable property
/// string representation; this codec gives them their declared type, without
/// coercing old text or throwing away a future type we cannot interpret.
public struct DatabaseField: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case text, number, checkbox, date, select, multiSelect, url
        public var id: String { rawValue }
        var label: String {
            switch self {
            case .text: "Text"; case .number: "Number"; case .checkbox: "Checkbox"
            case .date: "Date"; case .select: "Select"; case .multiSelect: "Multi-select"; case .url: "URL"
            }
        }
        var symbol: String {
            switch self {
            case .text: "text.alignleft"; case .number: "number"; case .checkbox: "checkmark.square"
            case .date: "calendar"; case .select: "arrowtriangle.down.circle"; case .multiSelect: "checklist"; case .url: "link"
            }
        }
    }
    public var id: UUID
    public var name: String
    /// Raw type is intentionally retained for forward compatibility.
    public var type: String
    public var options: [DatabaseOption]
    public init(id: UUID = UUID(), name: String, kind: Kind = .text, options: [DatabaseOption] = []) {
        self.id = id; self.name = name; type = kind.rawValue; self.options = options
    }
    var kind: Kind? { Kind(rawValue: type) }
    var key: String { id.uuidString.lowercased() }
}

public struct DatabaseFilter: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var field: String = "title"
    public var operation: String = "contains"
    public var value: String = ""
    static let operations = ["contains", "equals", "notEquals", "empty", "notEmpty", "greater", "less"]
    static func label(_ operation: String) -> String {
        switch operation {
        case "notEquals": "is not"; case "empty": "is empty"; case "notEmpty": "is not empty"
        case "greater": "is after / greater than"; case "less": "is before / less than"
        case "equals": "is"; default: "contains"
        }
    }
}
public struct DatabaseSort: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var field: String = "title"
    public var ascending = true
}
public struct DatabaseView: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String = "Table"
    public var layout: String = "table"
    public var columns: [String] = ["title", "type", "date"]
    public var filters: [DatabaseFilter] = []
    public var matchAny = false
    public var sorts: [DatabaseSort] = []
    public var groupBy: String? = nil
}

enum DatabaseValue: Equatable {
    case text(String), number(Decimal), checkbox(Bool), date(Date), select(UUID), multiSelect([UUID]), url(String)
}
enum DatabaseSchema {
    private static func legacyName(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    /// Legacy names are mapped only for plain text. Explicit field identities
    /// always win. Nothing is rewritten merely by opening a screen.
    static func fields(for list: ItemList, items: [Item], knownFields: [DatabaseField] = []) -> [DatabaseField] {
        var fields = list.databaseFields
        for item in items.filter({ $0.listId == list.id && $0.deletedAt == nil }).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            for property in item.customProperties {
                if let id = property.fieldID, fields.contains(where: { $0.id == id }) { continue }
                if property.fieldID == nil, fields.contains(where: { $0.type == "text" && legacyName($0.name) == legacyName(property.name) }) { continue }
                let id = property.fieldID ?? property.id
                if fields.contains(where: { $0.id == id }) { continue }
                var field = knownFields.first(where: { $0.id == id }) ?? DatabaseField(id: id, name: property.name)
                if property.fieldID != nil, !knownFields.contains(where: { $0.id == id }) {
                    field.type = property.fieldType ?? "text"; field.options = property.fieldOptions ?? []
                }
                let original = field.name
                var suffix = 2
                while fields.contains(where: { normalized($0.name) == normalized(field.name) }) {
                    field.name = "\(original) (\(suffix))"; suffix += 1
                }
                fields.append(field)
            }
        }
        return fields
    }
    static func property(_ field: DatabaseField, in item: Item) -> ItemCustomProperty? {
        item.customProperties.first { $0.fieldID == field.id || ($0.fieldID == nil && $0.id == field.id) }
            ?? item.customProperties.first { $0.fieldID == nil && field.type == "text" && legacyName($0.name) == legacyName(field.name) }
    }
    static func number(_ source: String) -> Decimal? {
        guard source.range(of: #"^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              let number = Decimal(string: source, locale: Locale(identifier: "en_US_POSIX")), !number.isNaN else { return nil }
        return number
    }
    static func decode(_ raw: String, field: DatabaseField) -> DatabaseValue? {
        guard !raw.isEmpty, let kind = field.kind else { return nil }
        switch kind {
        case .text: return .text(raw)
        case .number: return number(raw).map(DatabaseValue.number)
        case .checkbox: return raw == "true" ? .checkbox(true) : raw == "false" ? .checkbox(false) : nil
        case .date: return ISO8601.date(from: raw).map(DatabaseValue.date)
        case .url:
            guard let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
            return .url(raw)
        case .select:
            guard let id = UUID(uuidString: raw), field.options.contains(where: { $0.id == id }) else { return nil }
            return .select(id)
        case .multiSelect:
            guard let ids = try? JSONDecoder().decode([UUID].self, from: Data(raw.utf8)),
                  Set(ids).count == ids.count, ids.allSatisfy({ id in field.options.contains { $0.id == id } }) else { return nil }
            return .multiSelect(ids)
        }
    }
    static func display(_ raw: String, field: DatabaseField) -> String {
        switch decode(raw, field: field) {
        case .checkbox(let value): value ? "Yes" : "No"
        case .date(let date): date.formatted(date: .abbreviated, time: .omitted)
        case .select(let id): field.options.first { $0.id == id }?.name ?? raw
        case .multiSelect(let ids): field.options.filter { ids.contains($0.id) }.map(\.name).joined(separator: ", ")
        default: raw
        }
    }
    static func set(_ raw: String, field: DatabaseField, in item: inout Item) -> Bool {
        guard !item.hasCustomPropertyStorageConflict, field.kind != nil,
              raw.isEmpty || decode(raw, field: field) != nil else { return false }
        let existing = property(field, in: item)
        if raw.isEmpty {
            if let existing { item.customProperties.removeAll { $0.id == existing.id } }
            return true
        }
        var property = existing ?? ItemCustomProperty(name: field.name)
        property.fieldID = field.id; property.fieldType = field.type; property.fieldOptions = field.options
        property.name = field.name
        switch decode(raw, field: field) {
        case .number(let value): property.value = NSDecimalNumber(decimal: value).stringValue
        case .select(let id): property.value = id.uuidString
        case .multiSelect(let ids): property.value = String(data: (try? JSONEncoder().encode(ids)) ?? Data(), encoding: .utf8) ?? raw
        case .date(let value): property.value = ISO8601.string(from: value)
        default: property.value = raw
        }
        // Preserve the old property ID so unknown per-property YAML survives.
        if let index = item.customProperties.firstIndex(where: { $0.id == property.id }) { item.customProperties[index] = property }
        else { item.customProperties.append(property) }
        return true
    }
    static let builtins = ["title", "type", "done", "date", "priority", "flag", "tags", "section"]
    static func label(_ key: String, fields: [DatabaseField]) -> String {
        fields.first { $0.key == key }?.name ?? ["title": "Title", "type": "Type", "done": "Completed", "date": "Date", "priority": "Priority", "flag": "Flag", "tags": "Tags", "section": "Section"][key] ?? "Unavailable field"
    }
    static func raw(_ key: String, item: Item, list: ItemList, fields: [DatabaseField]) -> String {
        switch key {
        case "title": item.title
        case "type": item.type.rawValue
        case "done": item.isComplete ? "true" : "false"
        case "date": item.due.map { ISO8601.string(from: $0) } ?? ""
        case "priority": item.priority.rawValue
        case "flag": item.flagged ? "true" : "false"
        case "tags": item.tags.joined(separator: ", ")
        case "section": list.sections.first { $0.id.uuidString == item.section }?.name ?? ""
        default: fields.first { $0.key == key }.flatMap { property($0, in: item)?.value } ?? ""
        }
    }
}

enum DatabaseQuery {
    struct Row: Identifiable {
        let item: Item
        let depth: Int
        let isContext: Bool
        var id: UUID { item.id }
    }
    static func matches(_ item: Item, view: DatabaseView, list: ItemList, fields: [DatabaseField]) -> Bool {
        let results = view.filters.map { filter in
            let raw = DatabaseSchema.raw(filter.field, item: item, list: list, fields: fields)
            let value = fields.first { $0.key == filter.field }.map { DatabaseSchema.display(raw, field: $0) } ?? raw
            let lhs = DatabaseSchema.normalized(value), rhs = DatabaseSchema.normalized(filter.value)
            switch filter.operation {
            case "empty": return raw.isEmpty
            case "notEmpty": return !raw.isEmpty
            case "equals", "notEquals":
                let typed = fields.first { $0.key == filter.field }?.kind
                let equal: Bool
                if (typed == .date || filter.field == "date"), let a = ISO8601.date(from: raw), let b = ISO8601.date(from: filter.value) {
                    equal = Calendar.current.isDate(a, inSameDayAs: b)
                } else if typed == .number, !raw.isEmpty {
                    equal = compare(raw, filter.value, key: filter.field, fields: fields) == .orderedSame
                } else { equal = lhs == rhs || DatabaseSchema.normalized(raw) == rhs }
                return filter.operation == "equals" ? equal : !equal
            case "greater", "less":
                guard !raw.isEmpty else { return false }
                let order: ComparisonResult
                if (filter.field == "date" || fields.first(where: { $0.key == filter.field })?.kind == .date),
                   let a = ISO8601.date(from: raw), let b = ISO8601.date(from: filter.value) {
                    let lhsDay = Calendar.current.startOfDay(for: a), rhsDay = Calendar.current.startOfDay(for: b)
                    order = lhsDay == rhsDay ? .orderedSame : lhsDay < rhsDay ? .orderedAscending : .orderedDescending
                } else { order = compare(raw, filter.value, key: filter.field, fields: fields) }
                return filter.operation == "greater" ? order == .orderedDescending : order == .orderedAscending
            case "contains": return lhs.contains(rhs)
            default: return false
            }
        }
        return results.isEmpty || (view.matchAny ? results.contains(true) : results.allSatisfy { $0 })
    }
    static func compare(_ lhs: String, _ rhs: String, key: String, fields: [DatabaseField]) -> ComparisonResult {
        if key == "date" || fields.first(where: { $0.key == key })?.kind == .date,
           let a = ISO8601.date(from: lhs), let b = ISO8601.date(from: rhs) {
            return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
        }
        if key == "priority" {
            let rank = ["none": 0, "low": 1, "medium": 2, "high": 3]
            let a = rank[lhs] ?? 0, b = rank[rhs] ?? 0
            return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
        }
        if fields.first(where: { $0.key == key })?.kind == .number,
           let a = DatabaseSchema.number(lhs), let b = DatabaseSchema.number(rhs) {
            return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
        }
        if let field = fields.first(where: { $0.key == key }), field.kind == .select || field.kind == .multiSelect {
            return DatabaseSchema.display(lhs, field: field).localizedStandardCompare(DatabaseSchema.display(rhs, field: field))
        }
        return lhs.localizedStandardCompare(rhs)
    }
    static func sorted(_ items: [Item], view: DatabaseView, list: ItemList, fields: [DatabaseField]) -> [Item] {
        items.sorted { a, b in
            for sort in view.sorts {
                let lhs = DatabaseSchema.raw(sort.field, item: a, list: list, fields: fields)
                let rhs = DatabaseSchema.raw(sort.field, item: b, list: list, fields: fields)
                if lhs.isEmpty != rhs.isEmpty { return !lhs.isEmpty }
                let order = compare(lhs, rhs, key: sort.field, fields: fields)
                if order != .orderedSame { return sort.ascending ? order == .orderedAscending : order == .orderedDescending }
            }
            return a.sortIndex == b.sortIndex ? a.id.uuidString < b.id.uuidString : a.sortIndex < b.sortIndex
        }
    }
    static func rows(items: [Item], view: DatabaseView, list: ItemList, fields: [DatabaseField], collapsed: Set<UUID> = [], retaining: Set<UUID> = []) -> [Row] {
        let active = items.filter { $0.listId == list.id && $0.deletedAt == nil }
        let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let matching = Set(active.filter { retaining.contains($0.id) || matches($0, view: view, list: list, fields: fields) }.map(\.id))
        var visible = matching
        for id in matching {
            var parent = byID[id]?.parentId
            var visited = Set<UUID>()
            while let next = parent, visited.insert(next).inserted, let item = byID[next] {
                visible.insert(next); parent = item.parentId
            }
        }
        let children = Dictionary(grouping: active.filter { visible.contains($0.id) }, by: \.parentId)
        let roots = active.filter { visible.contains($0.id) && ($0.parentId == nil || byID[$0.parentId!] == nil) }
        var stack = sorted(roots, view: view, list: list, fields: fields).reversed().map { ($0, 0) }
        var visited = Set<UUID>(), result: [Row] = []
        while let (item, depth) = stack.popLast() {
            guard visited.insert(item.id).inserted else { continue }
            result.append(.init(item: item, depth: depth, isContext: !matching.contains(item.id)))
            if !collapsed.contains(item.id) || !view.filters.isEmpty {
                stack.append(contentsOf: sorted(children[item.id] ?? [], view: view, list: list, fields: fields).reversed().map { ($0, depth + 1) })
            }
        }
        return result
    }
}


enum DatabaseValueError: LocalizedError {
    case invalidValue, itemUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidValue: "Enter a valid value for this property."
        case .itemUnavailable: "This item is no longer available for editing."
        }
    }
}
