import Foundation

/// One scheduled occurrence in a recurring task or completable event.
///
/// Occurrences are deliberately lightweight frontmatter metadata. The item
/// remains the only Markdown document in the series, so completing a repeat
/// never duplicates its body or attachments.
public struct RecurrenceOccurrence: Equatable, Identifiable, Sendable, Codable {
    public enum Status: String, Codable, Sendable {
        case open
        case completed
        case missed
    }

    public var id: UUID
    public var scheduledAt: Date
    public var timeZone: String?
    public var status: Status
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        scheduledAt: Date,
        timeZone: String? = nil,
        status: Status,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.scheduledAt = scheduledAt
        self.timeZone = timeZone
        self.status = status
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case scheduledAt = "scheduled_at"
        case timeZone = "timezone"
        case status
        case completedAt = "completed_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let scheduled = try container.decode(String.self, forKey: .scheduledAt)
        guard let scheduledDate = ISO8601.date(from: scheduled) else {
            throw DecodingError.dataCorruptedError(
                forKey: .scheduledAt,
                in: container,
                debugDescription: "Invalid occurrence date: \(scheduled)"
            )
        }
        scheduledAt = scheduledDate
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
        status = try container.decode(Status.self, forKey: .status)
        if let completed = try container.decodeIfPresent(String.self, forKey: .completedAt) {
            guard let completedDate = ISO8601.date(from: completed) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .completedAt,
                    in: container,
                    debugDescription: "Invalid occurrence completion date: \(completed)"
                )
            }
            completedAt = completedDate
        } else {
            completedAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ISO8601.string(from: scheduledAt), forKey: .scheduledAt)
        try container.encodeIfPresent(timeZone, forKey: .timeZone)
        try container.encode(status, forKey: .status)
        if let completedAt {
            try container.encode(ISO8601.string(from: completedAt), forKey: .completedAt)
        }
    }
}

/// The single primitive in Lists. See PRODUCT-SPEC.md §2.1, §3.
///
/// Every item has a `type` (task / note / event) that determines
/// behavior, plus shared identity and metadata. The types are one durable
/// model wearing different control surfaces: a task is text plus a checkbox,
/// note is markdown text, and an event is text plus a time span (`due` =
/// start, `end` = finish).
///
/// On disk: one markdown file per item. The fields below are encoded into the
/// YAML frontmatter; `body` is the markdown content after the closing `---`.
/// `body` is intentionally absent from `CodingKeys` and is populated by
/// `FrontmatterCodec` separately.
public struct Item: Equatable, Identifiable, Sendable {
    // Identity
    public var id: UUID
    public var type: ItemType
    public var title: String
    public var calendarImport: CalendarImport? = nil
    public var body: String
    /// Optional text properties; older documents omit this block.
    public var customProperties: [ItemCustomProperty] = []
    /// Unrecognized YAML values, retained by FrontmatterCodec on every edit.
    public var frontmatterExtensions: [String: String] = [:]
    public var hasCustomPropertyStorageConflict = false

    // Placement
    public var listId: String
    public var section: String?
    public var parentId: UUID?
    public var tags: [String]
    /// Manual ordering within a list. Persisted; only honored by
    /// `ListViewPreferences.SortMode.manual`. Drag-to-reorder writes a
    /// dense 0..n sequence per parent group on the affected list. New
    /// items default to 0; ties fall back to load order (stable sort).
    public var sortIndex: Int

    // Provenance
    public var createdAt: Date
    public var modifiedAt: Date
    public var createdBy: String

    // Task-shared fields
    public var done: Bool
    public var completedAt: Date?
    public var due: Date?
    public var dueAllDay: Bool
    public var dueTimeZone: String?
    /// Event end (meaningful when `type == .event`). `due` is the start; `end`
    /// is always set by the app (the UI seeds and keeps an end for every event,
    /// so there is no user-facing "point event"). The field is optional on disk
    /// for backward compatibility with older files; the app seeds a sensible
    /// default if a file arrives without one.
    public var end: Date?
    /// Whether an event can be ticked off (meaningful when `type == .event`).
    /// The defining difference from a task is what *not doing it* means: a
    /// non-completable event (the default) has no failure state — when it
    /// passes it is simply past, never overdue. A completable event ("pick up
    /// the cake, 2–3pm") behaves like a task. Converting any type into an
    /// event creates a plain calendar event; completability is opt-in.
    public var completable: Bool
    public var priority: Priority
    public var flagged: Bool

    // Reminder + trigger blocks (optional)
    public var reminder: Reminder?
    public var recurrence: Recurrence?
    /// Compact, chronological history for this recurring document. Exactly
    /// one occurrence is normally `.open`; completed and missed entries are
    /// immutable history unless the user explicitly corrects them.
    public var recurrenceOccurrences: [RecurrenceOccurrence]
    public var triggers: Triggers?

    // Soft delete
    public var deletedAt: Date?

    public enum ItemType: String, Codable, Sendable, CaseIterable {
        case task, note, event
        public static var allCases: [Self] { [.task, .note, .event] }

        /// Permissive decode: an unknown raw value — a future type, or a
        /// corrupted field — maps to `.task` instead of throwing, so one stray
        /// value can never abort the whole-library load. The
        /// synthesized `encode(to:)` still writes the real raw value; a
        /// fallback-decoded item is only ever rewritten as `.task` if the user
        /// edits and saves it, so its file is otherwise left untouched.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = ItemType(rawValue: raw) ?? .task
        }
    }

    public enum Priority: String, Codable, Sendable, CaseIterable {
        case none, low, medium, high
    }

    /// Tasks and completable events use `done`; notes and calendar-only events never complete.
    public var isComplete: Bool {
        isComplete(at: .now)
    }

    /// Clock-injected form used by queries and tests that already evaluate a
    /// specific "now" for smart lists, reminders, or badge counts.
    public func isComplete(at now: Date) -> Bool {
        switch type {
        case .task:
            return done
        case .note:
            return false
        case .event:
            return completable && done
        }
    }

    /// A "rolled-off" past event: a pure *calendar* event (non-completable)
    /// whose end has already passed before the start of today. These drop out
    /// of list views unless "Show Past Events" is on — they're never lost, they
    /// can still be surfaced in views that explicitly show past events.
    ///
    /// Deliberately scoped to non-completable events only: a *completable* event
    /// you didn't tick is still actionable ("missed"), so it persists like an
    /// overdue task rather than rolling off. The end-of-day boundary means an
    /// event that ended earlier today stays visible through today, then drops.
    /// See PRODUCT-SPEC.md §3.
    public func isRolledOffPastEvent(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard type == .event, !completable else { return false }
        guard let endInstant = end ?? due else { return false }
        return endInstant <= calendar.startOfDay(for: now)
    }

    /// Overdue means unfinished actionable work whose due/start date is before
    /// today. Non-completable calendar events are never overdue; they are either
    /// happening, upcoming, or past.
    public func isOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let due else { return false }
        return due < calendar.startOfDay(for: now)
            && !isComplete(at: now)
            && !(type == .event && !completable)
    }

    /// Body text with markdown syntax stripped, trimmed of whitespace — for
    /// plain-text preview rows (static item row, and the inline editor's
    /// read-only notes preview). The full markdown lives on disk; this is
    /// display-only.
    public var plainTextBody: String {
        var s = body.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: #"(?m)^#{1,6} +"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"__(.+?)__"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*([^*\n]+)\*"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"_([^_\n]+)_"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"~~(.+?)~~"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`([^`\n]+)`"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]\n]+)\]\([^)\n]+\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?m)^[-*+] +"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?m)^> *"#, with: "", options: .regularExpression)
        return s
    }

    public init(
        id: UUID = UUID(),
        type: ItemType,
        title: String,
        body: String = "",
        listId: String,
        section: String? = nil,
        parentId: UUID? = nil,
        tags: [String] = [],
        createdAt: Date = .now,
        modifiedAt: Date? = nil,
        createdBy: String = "human",
        done: Bool = false,
        completedAt: Date? = nil,
        due: Date? = nil,
        dueAllDay: Bool = false,
        dueTimeZone: String? = nil,
        end: Date? = nil,
        completable: Bool = false,
        priority: Priority = .none,
        flagged: Bool = false,
        reminder: Reminder? = nil,
        recurrence: Recurrence? = nil,
        recurrenceOccurrences: [RecurrenceOccurrence] = [],
        triggers: Triggers? = nil,
        deletedAt: Date? = nil,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.listId = listId
        self.section = section
        self.parentId = parentId
        self.tags = tags
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.createdBy = createdBy
        self.done = done
        self.completedAt = completedAt
        self.due = due
        self.dueAllDay = dueAllDay
        self.dueTimeZone = dueTimeZone
        self.end = end
        self.completable = completable
        self.priority = priority
        self.flagged = flagged
        self.reminder = reminder
        self.recurrence = recurrence
        self.recurrenceOccurrences = recurrenceOccurrences
        self.triggers = triggers
        self.deletedAt = deletedAt
    }
}

/// Applies document-type conversion while preserving supported metadata.
enum ItemTypeTransition {
    static func apply(_ newType: Item.ItemType, to item: inout Item) {
        guard newType != item.type else { return }
        item.type = newType

        switch newType {
        case .event:
            item.completable = false
            EventDefaults.normalize(&item)
        case .task, .note:
            break
        }

        let keepsDone = newType == .task || (newType == .event && item.completable)
        if !keepsDone {
            item.done = false
            item.completedAt = nil
        }
    }
}

extension Item: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case type
        case title
        case customProperties = "custom_properties"
        case listId       = "list"
        case section
        case parentId     = "parent"
        case tags
        case createdAt    = "created_at"
        case modifiedAt   = "modified_at"
        case createdBy    = "created_by"
        case done
        case completedAt  = "completed_at"
        case due
        case dueAllDay    = "due_all_day"
        case dueTimeZone  = "due_timezone"
        case end
        case completable
        case priority
        case flagged
        case reminder
        case calendarImport
        case recurrence
        case recurrenceOccurrences = "recurrence_occurrences"
        case triggers
        case deletedAt    = "deleted_at"
        case sortIndex    = "sort_index"
    }

    static var frontmatterKeyNames: Set<String> { Set(CodingKeys.allCases.map(\.rawValue)) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id            = try c.decode(UUID.self,      forKey: .id)
        self.type          = try c.decode(ItemType.self,  forKey: .type)
        self.title         = try c.decode(String.self,    forKey: .title)
        self.body          = ""  // populated by FrontmatterCodec
        if c.contains(.customProperties) {
            if let properties = try? c.decode([ItemCustomProperty].self, forKey: .customProperties),
               Set(properties.map(\.id)).count == properties.count,
               properties.allSatisfy({ $0.hasValidName(among: properties) }) {
                self.customProperties = properties
            } else {
                self.hasCustomPropertyStorageConflict = true
            }
        }
        self.listId        = try c.decode(String.self,    forKey: .listId)
        self.section       = try c.decodeIfPresent(String.self, forKey: .section)
        self.parentId      = try c.decodeIfPresent(UUID.self,   forKey: .parentId)
        self.tags          = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.createdAt     = try Self.decodeDate(c, .createdAt)
        self.modifiedAt    = try Self.decodeDate(c, .modifiedAt)
        self.createdBy     = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? "human"
        self.done          = try c.decodeIfPresent(Bool.self,   forKey: .done) ?? false
        self.completedAt   = try Self.decodeDateIfPresent(c, .completedAt)
        self.due           = try Self.decodeDateIfPresent(c, .due)
        self.dueAllDay     = try c.decodeIfPresent(Bool.self, forKey: .dueAllDay) ?? false
        self.dueTimeZone   = try c.decodeIfPresent(String.self, forKey: .dueTimeZone)
        self.end           = try Self.decodeDateIfPresent(c, .end)
        self.completable   = try c.decodeIfPresent(Bool.self, forKey: .completable) ?? false
        self.priority      = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        self.flagged       = try c.decodeIfPresent(Bool.self, forKey: .flagged) ?? false
        self.calendarImport = try c.decodeIfPresent(CalendarImport.self, forKey: .calendarImport)
        self.reminder      = try c.decodeIfPresent(Reminder.self,  forKey: .reminder)
        self.recurrence    = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        if let lossy = try c.decodeIfPresent([LossyOccurrence].self, forKey: .recurrenceOccurrences) {
            self.recurrenceOccurrences = lossy.compactMap(\.value)
        } else {
            self.recurrenceOccurrences = []
        }
        self.triggers      = try c.decodeIfPresent(Triggers.self,   forKey: .triggers)
        self.deletedAt     = try Self.decodeDateIfPresent(c, .deletedAt)
        self.sortIndex     = try c.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(title, forKey: .title)
        if !customProperties.isEmpty && !hasCustomPropertyStorageConflict {
            try c.encode(customProperties, forKey: .customProperties)
        }
        try c.encode(listId, forKey: .listId)
        try c.encodeIfPresent(section, forKey: .section)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encode(ISO8601.string(from: createdAt), forKey: .createdAt)
        try c.encode(ISO8601.string(from: modifiedAt), forKey: .modifiedAt)
        try c.encode(createdBy, forKey: .createdBy)
        if done { try c.encode(true, forKey: .done) }
        if let completedAt {
            try c.encode(ISO8601.string(from: completedAt), forKey: .completedAt)
        }
        if let due {
            // An all-day due is a calendar day, not an instant: encoded as
            // `yyyy-MM-dd` in the local calendar so a reload or timezone move
            // can never shift it onto an adjacent day.
            // Timed dues stay full instants.
            try c.encode(dueAllDay ? ISO8601.localDayString(from: due)
                                   : ISO8601.string(from: due), forKey: .due)
        }
        if dueAllDay { try c.encode(true, forKey: .dueAllDay) }
        try c.encodeIfPresent(dueTimeZone, forKey: .dueTimeZone)
        if let end {
            // Same all-day rule as `due`: an all-day event's end is a day.
            try c.encode(dueAllDay ? ISO8601.localDayString(from: end)
                                   : ISO8601.string(from: end), forKey: .end)
        }
        if completable { try c.encode(true, forKey: .completable) }
        if priority != .none { try c.encode(priority, forKey: .priority) }
        if flagged { try c.encode(true, forKey: .flagged) }
        try c.encodeIfPresent(calendarImport, forKey: .calendarImport)
        try c.encodeIfPresent(reminder, forKey: .reminder)
        try c.encodeIfPresent(recurrence, forKey: .recurrence)
        if !recurrenceOccurrences.isEmpty {
            try c.encode(recurrenceOccurrences, forKey: .recurrenceOccurrences)
        }
        try c.encodeIfPresent(triggers, forKey: .triggers)

        if let deletedAt {
            try c.encode(ISO8601.string(from: deletedAt), forKey: .deletedAt)
        }
        if sortIndex != 0 {
            try c.encode(sortIndex, forKey: .sortIndex)
        }
    }

    private static func decodeDate(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> Date {
        let s = try c.decode(String.self, forKey: key)
        guard let date = ISO8601.date(from: s) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: c,
                debugDescription: "Invalid ISO 8601 date: \(s)"
            )
        }
        return date
    }


    private struct LossyOccurrence: Decodable {
        let value: RecurrenceOccurrence?
        init(from decoder: Decoder) throws {
            value = try? RecurrenceOccurrence(from: decoder)
        }
    }

    private static func decodeDateIfPresent(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> Date? {
        // Absent -> nil is fine, but present-and-invalid must throw rather than
        // silently dropping the value. A bad `deleted_at` mapped to nil would
        // resurrect a deleted item; throwing routes the file to quarantine
        // instead, keeping it out of the live set.
        guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = ISO8601.date(from: s) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: c,
                debugDescription: "Invalid ISO 8601 date: \(s)"
            )
        }
        return date
    }
}


public struct ItemCustomProperty: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), name: String, value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }

    public func hasValidName(among properties: [Self]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !properties.contains {
            $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }
}
