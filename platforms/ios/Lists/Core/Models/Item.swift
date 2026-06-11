import Foundation

/// The single primitive in Lists. See PRODUCT-SPEC.md §2.1, §3.
///
/// Every item has a `type` (task / habit / note / event) that determines
/// behavior, plus a shared shape (title, body, tags, dates, etc.). The types
/// are one thing wearing different control surfaces: a task is a note plus a
/// checkbox, a habit is a note plus a cycle counter, an event is a note plus
/// a time span (`due` = start, optional `end`).
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
    /// Event end (meaningful when `type == .event`). An event is
    /// "start + optional end": `due` is the start, and a missing `end` is a
    /// point event ("Dentist 3pm"). Deliberately calendar-shaped — start /
    /// end / all-day translate 1:1 to iCal fields when import/export arrives.
    public var end: Date?
    /// Whether an event can be ticked off (meaningful when `type == .event`).
    /// The defining difference from a task is what *not doing it* means: a
    /// non-completable event (the default) has no failure state — when it
    /// passes it is simply past, never overdue. A completable event ("pick up
    /// the cake, 2–3pm") behaves like a task. Converting a task into an event
    /// must set this true so a done-state never silently disappears.
    public var completable: Bool
    public var priority: Priority
    public var flagged: Bool

    // Reminder + trigger blocks (optional)
    public var reminder: Reminder?
    public var recurrence: Recurrence?
    public var triggers: Triggers?

    // Habit fields (only meaningful when type == .habit)
    public var frequency: HabitFrequency?
    public var goalPerCycle: Int
    /// Stored source of truth for habit history: one timestamped event per
    /// completion. Per-cycle counts are derived (see `completionLog`).
    public var completions: [HabitCompletion]
    public var showStreak: Bool
    /// When true (only meaningful for `.weekly` / `.monthly`), `goalPerCycle`
    /// reads as "N times across the cycle" — a flexible "3 times a week" goal
    /// rather than N completions on a single day.
    public var flexibleGoal: Bool

    /// Per-cycle completion counts, derived by grouping `completions` through
    /// `HabitCycle.key`. Preserves the original `[cycleKey: count]` read API that
    /// rows, the heatmap, stats and `isComplete` depend on, so the move to
    /// timestamped events ripples no further than the writers.
    ///
    /// MODEL-HABIT-1: counts are bucketed on the *normalized* cadence
    /// (daily / weekly / monthly) — the same basis the detail screen, heatmap
    /// and `HabitStats` use — so the row checkmark and the detail screen can
    /// never disagree about whether a cycle is complete.
    public var completionLog: [String: Int] {
        guard let frequency = frequency?.normalizedForHabit else { return [:] }
        return Dictionary(grouping: completions, by: { HabitCycle.key(for: frequency, on: $0.at) })
            .mapValues(\.count)
    }

    // Soft delete
    public var deletedAt: Date?

    public enum ItemType: String, Codable, Sendable, CaseIterable {
        case task, habit, note, event

        /// Permissive decode (DI-1 / AGENT-1): an unknown raw value — a future
        /// type, or a corrupted field — maps to `.task` instead of throwing, so
        /// one stray value can never abort the whole-library load. The
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

    /// Unified completion check. Tasks use `done`; habits compare the
    /// current cycle's count against `goalPerCycle`; notes are never
    /// complete; events complete only when `completable` — a non-completable
    /// event that has passed isn't "complete", it's just past. See
    /// PRODUCT-SPEC.md §3.
    public var isComplete: Bool {
        switch type {
        case .task:
            return done
        case .habit:
            guard let frequency = frequency?.normalizedForHabit else { return false }
            let key = HabitCycle.key(for: frequency, on: .now)
            return (completionLog[key] ?? 0) >= goalPerCycle
        case .note:
            return false
        case .event:
            return completable && done
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
        end: Date? = nil,
        completable: Bool = false,
        priority: Priority = .none,
        flagged: Bool = false,
        reminder: Reminder? = nil,
        recurrence: Recurrence? = nil,
        triggers: Triggers? = nil,
        frequency: HabitFrequency? = nil,
        goalPerCycle: Int = 1,
        completions: [HabitCompletion] = [],
        showStreak: Bool = true,
        flexibleGoal: Bool = false,
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
        self.triggers = triggers
        self.frequency = frequency
        self.goalPerCycle = goalPerCycle
        self.completions = completions
        self.showStreak = showStreak
        self.flexibleGoal = flexibleGoal
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
        case end
        case completable
        case priority
        case flagged
        case reminder
        case recurrence
        case triggers
        case frequency
        case goalPerCycle = "goal_per_cycle"
        case completionLog = "completion_log"   // legacy: decoded for migration, never re-written
        case completions
        case showStreak   = "show_streak"
        case flexibleGoal = "flexible_goal"
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
        self.end           = try Self.decodeDateIfPresent(c, .end)
        self.completable   = try c.decodeIfPresent(Bool.self, forKey: .completable) ?? false
        self.priority      = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        self.flagged       = try c.decodeIfPresent(Bool.self, forKey: .flagged) ?? false
        self.reminder      = try c.decodeIfPresent(Reminder.self,  forKey: .reminder)
        self.recurrence    = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        self.triggers      = try c.decodeIfPresent(Triggers.self,   forKey: .triggers)
        self.frequency     = try c.decodeIfPresent(HabitFrequency.self, forKey: .frequency)
        self.goalPerCycle  = try c.decodeIfPresent(Int.self, forKey: .goalPerCycle) ?? 1
        // New shape: timestamped events. A single malformed event is skipped
        // (LossyCompletion) rather than aborting the whole habit. Falls back to a
        // one-way migration of the legacy `completion_log` count dictionary.
        if let lossy = try c.decodeIfPresent([LossyCompletion].self, forKey: .completions) {
            self.completions = lossy.compactMap(\.value)
        } else if let legacy = try c.decodeIfPresent([String: Int].self, forKey: .completionLog) {
            self.completions = HabitCompletion.migrate(legacyLog: legacy)
        } else {
            self.completions = []
        }
        self.showStreak    = try c.decodeIfPresent(Bool.self, forKey: .showStreak) ?? true
        self.flexibleGoal  = try c.decodeIfPresent(Bool.self, forKey: .flexibleGoal) ?? false
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
            // MODEL-ALLDAY-1: an all-day due is a calendar DAY, not an
            // instant — encoded as `yyyy-MM-dd` (local calendar) so a reload
            // or timezone move can never shift it onto an adjacent day.
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
        try c.encodeIfPresent(reminder, forKey: .reminder)
        try c.encodeIfPresent(recurrence, forKey: .recurrence)
        try c.encodeIfPresent(triggers, forKey: .triggers)

        if type == .habit {
            try c.encodeIfPresent(frequency, forKey: .frequency)
            try c.encode(goalPerCycle, forKey: .goalPerCycle)
            try c.encode(showStreak, forKey: .showStreak)
            if flexibleGoal { try c.encode(true, forKey: .flexibleGoal) }
        }
        // MODEL-TYPEFLIP-1: completions are written for ANY type, so a future
        // habit→task conversion can never silently strip months of habit
        // history on its next save. Decode already tolerates them everywhere.
        if !completions.isEmpty {
            try c.encode(completions, forKey: .completions)
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

    /// Decodes one element of the `completions` array tolerantly: a malformed
    /// event yields `nil` (and is filtered out) instead of throwing and taking
    /// the whole habit down with it. Decoding the array structure still succeeds
    /// because each element is a mapping; only the inner value is salvaged.
    private struct LossyCompletion: Decodable {
        let value: HabitCompletion?
        init(from decoder: Decoder) throws {
            value = try? HabitCompletion(from: decoder)
        }
    }

    private static func decodeDateIfPresent(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> Date? {
        // DI-3: absent → nil (fine), but present-but-invalid must throw rather
        // than silently dropping the value. A bad `deleted_at` mapped to nil
        // would resurrect a deleted item; throwing routes the file to DI-1's
        // quarantine instead, keeping it out of the live set (fail-safe).
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
