import Foundation

/// The single primitive in Lists. See PRODUCT-SPEC.md §2.1, §3.
///
/// Every item has a `type` (task / habit / note) that determines behavior,
/// plus a shared shape (title, body, tags, dates, etc.).
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
    public var body: String

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
    public var priority: Priority
    public var flagged: Bool

    // Reminder + trigger blocks (optional)
    public var reminder: Reminder?
    public var recurrence: Recurrence?
    public var triggers: Triggers?

    // Habit fields (only meaningful when type == .habit)
    public var frequency: HabitFrequency?
    public var goalPerCycle: Int
    public var completionLog: [String: Int]
    public var showStreak: Bool

    // Soft delete
    public var deletedAt: Date?

    public enum ItemType: String, Codable, Sendable, CaseIterable {
        case task, habit, note
    }

    public enum Priority: String, Codable, Sendable, CaseIterable {
        case none, low, medium, high
    }

    /// Unified completion check. Tasks use `done`; habits compare the
    /// current cycle's count against `goalPerCycle`; notes are never
    /// complete. See PRODUCT-SPEC.md §3.
    public var isComplete: Bool {
        switch type {
        case .task:
            return done
        case .habit:
            guard let frequency else { return false }
            let key = HabitCycle.key(for: frequency, on: .now)
            return (completionLog[key] ?? 0) >= goalPerCycle
        case .note:
            return false
        }
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
        priority: Priority = .none,
        flagged: Bool = false,
        reminder: Reminder? = nil,
        recurrence: Recurrence? = nil,
        triggers: Triggers? = nil,
        frequency: HabitFrequency? = nil,
        goalPerCycle: Int = 1,
        completionLog: [String: Int] = [:],
        showStreak: Bool = true,
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
        self.priority = priority
        self.flagged = flagged
        self.reminder = reminder
        self.recurrence = recurrence
        self.triggers = triggers
        self.frequency = frequency
        self.goalPerCycle = goalPerCycle
        self.completionLog = completionLog
        self.showStreak = showStreak
        self.deletedAt = deletedAt
    }
}

extension Item: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
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
        case priority
        case flagged
        case reminder
        case recurrence
        case triggers
        case frequency
        case goalPerCycle = "goal_per_cycle"
        case completionLog = "completion_log"
        case showStreak   = "show_streak"
        case deletedAt    = "deleted_at"
        case sortIndex    = "sort_index"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id            = try c.decode(UUID.self,      forKey: .id)
        self.type          = try c.decode(ItemType.self,  forKey: .type)
        self.title         = try c.decode(String.self,    forKey: .title)
        self.body          = ""  // populated by FrontmatterCodec
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
        self.priority      = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        self.flagged       = try c.decodeIfPresent(Bool.self, forKey: .flagged) ?? false
        self.reminder      = try c.decodeIfPresent(Reminder.self,  forKey: .reminder)
        self.recurrence    = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        self.triggers      = try c.decodeIfPresent(Triggers.self,   forKey: .triggers)
        self.frequency     = try c.decodeIfPresent(HabitFrequency.self, forKey: .frequency)
        self.goalPerCycle  = try c.decodeIfPresent(Int.self, forKey: .goalPerCycle) ?? 1
        self.completionLog = try c.decodeIfPresent([String: Int].self, forKey: .completionLog) ?? [:]
        self.showStreak    = try c.decodeIfPresent(Bool.self, forKey: .showStreak) ?? true
        self.deletedAt     = try Self.decodeDateIfPresent(c, .deletedAt)
        self.sortIndex     = try c.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(title, forKey: .title)
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
            try c.encode(ISO8601.string(from: due), forKey: .due)
        }
        if dueAllDay { try c.encode(true, forKey: .dueAllDay) }
        try c.encodeIfPresent(dueTimeZone, forKey: .dueTimeZone)
        if priority != .none { try c.encode(priority, forKey: .priority) }
        if flagged { try c.encode(true, forKey: .flagged) }
        try c.encodeIfPresent(reminder, forKey: .reminder)
        try c.encodeIfPresent(recurrence, forKey: .recurrence)
        try c.encodeIfPresent(triggers, forKey: .triggers)

        if type == .habit {
            try c.encodeIfPresent(frequency, forKey: .frequency)
            try c.encode(goalPerCycle, forKey: .goalPerCycle)
            if !completionLog.isEmpty {
                try c.encode(completionLog, forKey: .completionLog)
            }
            try c.encode(showStreak, forKey: .showStreak)
        }
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

    private static func decodeDateIfPresent(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> Date? {
        guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return ISO8601.date(from: s)
    }
}
