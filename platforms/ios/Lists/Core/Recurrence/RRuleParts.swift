enum RRuleParts {
    static func parse(_ rrule: String) -> [String: String] {
        Dictionary(
            rrule.split(separator: ";").compactMap { part -> (String, String)? in
                let keyValue = part.split(separator: "=", maxSplits: 1).map(String.init)
                guard keyValue.count == 2 else { return nil }
                return (keyValue[0].uppercased(), keyValue[1])
            },
            uniquingKeysWith: { _, new in new }
        )
    }

    static func splitUntil(from rrule: String) -> (base: String, until: String?) {
        var baseSegments: [String] = []
        var until: String?

        for segment in rrule.split(separator: ";", omittingEmptySubsequences: false).map(String.init) {
            let keyValue = segment.split(separator: "=", maxSplits: 1).map(String.init)
            guard keyValue.count == 2 else {
                baseSegments.append(segment)
                continue
            }

            if keyValue[0].uppercased() == "UNTIL" {
                until = keyValue[1]
            } else {
                baseSegments.append(segment)
            }
        }

        return (baseSegments.joined(separator: ";"), until)
    }
}
