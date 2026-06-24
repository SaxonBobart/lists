import Foundation

/// A single timestamped habit completion event.
///
/// This is the stored source of truth for a habit's history (`Item.completions`).
/// Per-cycle counts — the thing the UI shows as "2 of 3 this week" — are *derived*
/// by grouping these events through `HabitCycle.key(for:on:)` (see the computed
/// `Item.completionLog`). Storing the instant (not just a per-day count) is what
/// lets the Log screen edit the time/date of, or delete, any individual completion.
public struct HabitCompletion: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// The absolute instant the completion is attributed to. Editing this in the
    /// Log moves the completion to a different time and/or cycle.
    public var at: Date

    public init(id: UUID = UUID(), at: Date) {
        self.id = id
        self.at = at
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case at
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A missing id is tolerated (synthesize one) so a hand-edited file still
        // loads; an invalid timestamp throws so the lossy array decode in
        // `Item` can skip just this element.
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let raw = try c.decode(String.self, forKey: .at)
        guard let date = ISO8601.date(from: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .at, in: c,
                debugDescription: "Invalid ISO 8601 date: \(raw)"
            )
        }
        self.at = date
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ISO8601.string(from: at), forKey: .at)
    }
}

// MARK: - Legacy migration

extension HabitCompletion {
    /// One-way migration from the legacy `completion_log: [cycleKey: count]` shape
    /// into timestamped events. Each count becomes that many events placed at a
    /// representative instant *inside* the original cycle, so regrouping them via
    /// `HabitCycle.key` reproduces the original counts exactly. Events within a
    /// cycle are spread one second apart for stable ordering.
    ///
    /// Each key is parsed by its *shape* (day / hour / week / month / quarter /
    /// half / year), not by the habit's current frequency. A habit whose cadence
    /// was changed after counts were recorded must not have that history
    /// silently dropped because the old keys no longer match the current
    /// frequency's format.
    public static func migrate(legacyLog: [String: Int]) -> [HabitCompletion] {
        var result: [HabitCompletion] = []
        for (key, count) in legacyLog.sorted(by: { $0.key < $1.key }) where count > 0 {
            guard let base = representativeDate(forCycleKey: key) else { continue }
            for i in 0..<count {
                result.append(HabitCompletion(at: base.addingTimeInterval(TimeInterval(i))))
            }
        }
        return result
    }

    /// A stable instant guaranteed to land inside the cycle named by `key`,
    /// inferred from the key's shape. Every cycle-key format `HabitCycle.key`
    /// has ever produced is syntactically distinct, so the shapes dispatch
    /// unambiguously. All calendars are UTC, matching `HabitCycle.key`.
    private static func representativeDate(forCycleKey key: String) -> Date? {
        if key.contains("T") {                                   // hourly: yyyy-MM-ddTHH:00
            let parts = key.components(separatedBy: "T")
            guard parts.count == 2 else { return nil }
            let day = parts[0].components(separatedBy: "-")
            guard day.count == 3, let y = Int(day[0]), let m = Int(day[1]), let d = Int(day[2]),
                  let hour = Int(parts[1].prefix(2)) else { return nil }
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            return cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: 30))
        }
        if key.contains("-W") {                                  // weekly: yyyy-Www
            let p = key.components(separatedBy: "-W")
            guard p.count == 2, let year = Int(p[0]), let week = Int(p[1]) else { return nil }
            var comps = DateComponents()
            comps.yearForWeekOfYear = year
            comps.weekOfYear = week
            comps.weekday = 4          // mid-week (Wednesday), safe from boundaries
            comps.hour = 12
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            return cal.date(from: comps)
        }
        if key.contains("-Q") {                                  // quarterly: yyyy-Qn
            let p = key.components(separatedBy: "-Q")
            guard p.count == 2, let y = Int(p[0]), let q = Int(p[1]), (1...4).contains(q) else { return nil }
            return utcNoon(year: y, month: 3 * (q - 1) + 2, day: 15)   // mid-quarter
        }
        if key.contains("-H") {                                  // half-yearly: yyyy-Hn
            let p = key.components(separatedBy: "-H")
            guard p.count == 2, let y = Int(p[0]), let h = Int(p[1]), (1...2).contains(h) else { return nil }
            return utcNoon(year: y, month: h == 1 ? 3 : 9, day: 15)    // mid-half
        }
        let p = key.components(separatedBy: "-")
        switch p.count {
        case 3:                                                  // daily: yyyy-MM-dd
            guard let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
            return utcNoon(year: y, month: m, day: d)
        case 2:                                                  // monthly: yyyy-MM
            guard let y = Int(p[0]), let m = Int(p[1]) else { return nil }
            return utcNoon(year: y, month: m, day: 15)
        case 1:                                                  // yearly: yyyy
            guard let y = Int(key) else { return nil }
            return utcNoon(year: y, month: 7, day: 1)            // mid-year
        default:
            return nil
        }
    }

    private static func utcNoon(year: Int, month: Int, day: Int) -> Date? {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}
