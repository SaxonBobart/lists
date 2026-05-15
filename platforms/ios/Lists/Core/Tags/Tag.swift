import Foundation

/// Pure helpers for the flat multi-tag scheme. Each item carries a
/// `[String]` of tags. Tags are case-insensitive for identity but the
/// user's chosen casing is preserved on display.
enum Tag {

    /// Pull `#tag` mentions out of free-form text. Returns the text with
    /// the `#tag` tokens removed (whitespace collapsed) plus the list of
    /// extracted tag names (without `#`, original casing preserved,
    /// deduplicated case-insensitively).
    ///
    /// Recognised tokens are `#` followed by one or more letters, digits,
    /// `_` or `-`. Trailing punctuation (`. , ; : ! ?`) is left in place;
    /// only the alphanumeric run after `#` is consumed.
    static func extractInline(from text: String) -> (cleaned: String, tags: [String]) {
        // (?<![\w]) makes sure we only match a free-standing `#tag`, not
        // the `#` inside an existing word.
        let pattern = #"(?<![\w])#([A-Za-z0-9_-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return (text, []) }

        var tags: [String] = []
        var seen: Set<String> = []
        for m in matches where m.numberOfRanges >= 2 {
            let tag = ns.substring(with: m.range(at: 1))
            let lower = tag.lowercased()
            if !seen.contains(lower) {
                seen.insert(lower)
                tags.append(tag)
            }
        }

        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        let collapsed = stripped
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return (collapsed.trimmingCharacters(in: .whitespacesAndNewlines), tags)
    }

    /// Cleans raw user input into a canonical tag, or nil if empty.
    /// Trims whitespace, strips a leading `#`, replaces `/` with `-`
    /// (slashes are not hierarchy markers in v1), collapses internal
    /// whitespace runs to a single space.
    static func sanitize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") {
            s.removeFirst()
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        s = s.replacingOccurrences(of: "/", with: "-")
        let collapsed = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// Snap the user's casing to whatever variant already exists in
    /// `existing`, case-insensitively. New tags keep the user's casing.
    static func snapCasing(_ tag: String, existing: [String]) -> String {
        let lower = tag.lowercased()
        if let match = existing.first(where: { $0.lowercased() == lower }) {
            return match
        }
        return tag
    }

    /// Append `tag` to `tags` if not already present (case-insensitive).
    /// Returns the updated array. Sanitization is the caller's job.
    static func appending(_ tag: String, to tags: [String]) -> [String] {
        let lower = tag.lowercased()
        if tags.contains(where: { $0.lowercased() == lower }) { return tags }
        return tags + [tag]
    }

    /// Reorder `tags` so tags that frequently appear together end up
    /// adjacent. Greedy chain: start with the most-used tag, walk to
    /// the unvisited tag that co-occurs with it most often. When a
    /// chain dead-ends, jump to the next-most-used unvisited tag and
    /// continue. Display casing is preserved from the input.
    static func orderByRelation(_ tags: [String], itemTagSets: [[String]]) -> [String] {
        guard tags.count > 2 else { return tags }
        let lowered = tags.map { $0.lowercased() }
        let display = Dictionary(uniqueKeysWithValues: zip(lowered, tags))

        var count: [String: Int] = [:]
        var pair: [String: [String: Int]] = [:]
        for set in itemTagSets {
            let lower = set.map { $0.lowercased() }
            for t in lower where display[t] != nil {
                count[t, default: 0] += 1
            }
            for i in 0..<lower.count {
                for j in (i + 1)..<lower.count {
                    let a = lower[i], b = lower[j]
                    guard display[a] != nil, display[b] != nil else { continue }
                    pair[a, default: [:]][b, default: 0] += 1
                    pair[b, default: [:]][a, default: 0] += 1
                }
            }
        }

        var unvisited = Set(lowered)
        var result: [String] = []

        while !unvisited.isEmpty {
            let start = unvisited.max { lhs, rhs in
                let lc = count[lhs, default: 0], rc = count[rhs, default: 0]
                if lc != rc { return lc < rc }
                return lhs > rhs
            }!
            unvisited.remove(start)
            result.append(start)
            var current = start

            while true {
                let neighbors = pair[current] ?? [:]
                let pick = neighbors
                    .filter { unvisited.contains($0.key) }
                    .max { lhs, rhs in
                        if lhs.value != rhs.value { return lhs.value < rhs.value }
                        let lc = count[lhs.key, default: 0]
                        let rc = count[rhs.key, default: 0]
                        if lc != rc { return lc < rc }
                        return lhs.key > rhs.key
                    }
                guard let pick else { break }
                unvisited.remove(pick.key)
                result.append(pick.key)
                current = pick.key
            }
        }

        return result.compactMap { display[$0] }
    }
}
