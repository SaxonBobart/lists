import Foundation

/// Display label for the Time Zone row.
enum TimeZoneLabel {
    static func display(for identifier: String?) -> String {
        let id = identifier ?? TimeZone.current.identifier
        let last = id.split(separator: "/").last.map(String.init) ?? id
        return last.replacingOccurrences(of: "_", with: " ")
    }
}
