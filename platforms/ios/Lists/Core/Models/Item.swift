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
/// Every item has a `type` (task / habit / note / event / canvas) that determines
/// behavior, plus shared identity and metadata. The types are one durable
/// model wearing different control surfaces: a task is text plus a checkbox,
/// a habit is title/metadata plus a cycle counter and completion history, a
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
    public var body: String
    /// Portable JSON Canvas document owned by a canvas item. The path is
    /// relative to the Lists library root so a library can be moved without
    /// rewriting item metadata. Canvas items keep their lightweight Markdown
    /// wrapper for shared Lists metadata while the creative document remains
    /// a real `.canvas` file that other JSON Canvas tools can open.
    public var canvasPath: String?

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
    /// Durable link from a materialized recurring occurrence to the item that
    /// produced it. This makes completion retries idempotent even when enough
    /// time has passed that the next calculated date would otherwise change.
    public var recurrenceSourceId: UUID?
    /// Written onto the source only in the root-last completion commit. An open
    /// source with an unlinked child is therefore an interrupted transaction;
    /// an intentionally unticked source retains this link and does not rewrite
    /// a successor the user may since have edited.
    public var recurrenceSuccessorId: UUID?
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
    /// Counts are bucketed on the *normalized* cadence (daily / weekly /
    /// monthly) — the same basis the detail screen, heatmap and `HabitStats`
    /// use — so the row checkmark and the detail screen can never disagree
    /// about whether a cycle is complete.
    public var completionLog: [String: Int] {
        guard let frequency = frequency?.normalizedForHabit else { return [:] }
        return Dictionary(grouping: completions, by: { HabitCycle.key(for: frequency, on: $0.at) })
            .mapValues(\.count)
    }

    // Soft delete
    public var deletedAt: Date?

    public enum ItemType: String, Codable, Sendable, CaseIterable {
        case task, habit, note, event, canvas

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

    /// Unified completion check. Tasks use `done`; habits compare the
    /// current cycle's count against `goalPerCycle`; notes are never
    /// complete; events complete only when `completable` — a non-completable
    /// event that has passed isn't "complete", it's just past. See
    /// PRODUCT-SPEC.md §3.
    public var isComplete: Bool {
        isComplete(at: .now)
    }

    /// Clock-injected form used by queries and tests that already evaluate a
    /// specific "now" for habits, smart lists, reminders, or badge counts.
    public func isComplete(at now: Date) -> Bool {
        switch type {
        case .task:
            return done
        case .habit:
            guard let frequency = frequency?.normalizedForHabit else { return false }
            let key = HabitCycle.key(for: frequency, on: now)
            return (completionLog[key] ?? 0) >= goalPerCycle
        case .note:
            return false
        case .event:
            return completable && done
        case .canvas:
            return false
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
        guard type != .habit else { return false }
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
        canvasPath: String? = nil,
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
        recurrenceSourceId: UUID? = nil,
        recurrenceSuccessorId: UUID? = nil,
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
        self.canvasPath = canvasPath
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
        self.recurrenceSourceId = recurrenceSourceId
        self.recurrenceSuccessorId = recurrenceSuccessorId
        self.triggers = triggers
        self.frequency = frequency
        self.goalPerCycle = goalPerCycle
        self.completions = completions
        self.showStreak = showStreak
        self.flexibleGoal = flexibleGoal
        self.deletedAt = deletedAt
    }
}

/// Applies the user-visible rules for changing an existing item's type while
/// retaining fields that are temporarily inactive. A habit does not display a
/// Markdown body, but its body and completion history remain durable so a
/// later type change cannot silently destroy user data.
enum ItemTypeTransition {
    static func apply(_ newType: Item.ItemType, to item: inout Item) {
        guard newType != item.type else { return }
        item.type = newType

        switch newType {
        case .event:
            item.completable = false
            EventDefaults.normalize(&item)
        case .habit:
            item.frequency = item.frequency?.normalizedForHabit ?? .daily
            item.goalPerCycle = max(1, item.goalPerCycle)
            item.completable = false
            item.end = nil
        case .task, .note, .canvas:
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
    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case canvasPath    = "canvas_path"
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
        case recurrenceOccurrences = "recurrence_occurrences"
        case recurrenceSourceId = "recurrence_source"
        case recurrenceSuccessorId = "recurrence_successor"
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
        self.canvasPath    = try c.decodeIfPresent(String.self, forKey: .canvasPath)
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
        if let lossy = try c.decodeIfPresent([LossyOccurrence].self, forKey: .recurrenceOccurrences) {
            self.recurrenceOccurrences = lossy.compactMap(\.value)
        } else {
            self.recurrenceOccurrences = []
        }
        self.recurrenceSourceId = try c.decodeIfPresent(UUID.self, forKey: .recurrenceSourceId)
        self.recurrenceSuccessorId = try c.decodeIfPresent(UUID.self, forKey: .recurrenceSuccessorId)
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
        try c.encodeIfPresent(canvasPath, forKey: .canvasPath)
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
        try c.encodeIfPresent(reminder, forKey: .reminder)
        try c.encodeIfPresent(recurrence, forKey: .recurrence)
        if !recurrenceOccurrences.isEmpty {
            try c.encode(recurrenceOccurrences, forKey: .recurrenceOccurrences)
        }
        try c.encodeIfPresent(recurrenceSourceId, forKey: .recurrenceSourceId)
        try c.encodeIfPresent(recurrenceSuccessorId, forKey: .recurrenceSuccessorId)
        try c.encodeIfPresent(triggers, forKey: .triggers)

        if type == .habit {
            try c.encodeIfPresent(frequency, forKey: .frequency)
            try c.encode(goalPerCycle, forKey: .goalPerCycle)
            try c.encode(showStreak, forKey: .showStreak)
            if flexibleGoal { try c.encode(true, forKey: .flexibleGoal) }
        }
        // Completions are written for any type, so changing an item's type never
        // silently strips habit history on its next save. Decode already
        // tolerates them everywhere.
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
