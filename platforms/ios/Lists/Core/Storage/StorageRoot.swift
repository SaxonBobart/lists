import Foundation

/// Resolves the on-disk root for the Lists library.
///
/// On iOS this is `<app sandbox>/Documents/Lists/` — app-private (NOT in
/// Files.app, NOT iCloud Drive). See `AGENTS.md` for the storage policy.
public enum StorageRoot {
    public static func defaultListsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--top-reveal-property-sample-data") {
            return docs.appendingPathComponent("Lists-Top-Reveal-Properties-V1", isDirectory: true)
        }
        if ProcessInfo.processInfo.arguments.contains("--document-first-sample-data") {
            return docs.appendingPathComponent("Lists-Document-First-Samples-V1", isDirectory: true)
        }
        if ProcessInfo.processInfo.arguments.contains("--collection-navigation-sample-data") {
            return docs.appendingPathComponent("Lists-Collection-Navigation-Samples-V1", isDirectory: true)
        }
        if ProcessInfo.processInfo.arguments.contains("--note-property-sample-data") {
            return docs.appendingPathComponent("Lists-Note-Property-Samples-V1", isDirectory: true)
        }
        if ProcessInfo.processInfo.arguments.contains("--attachment-sample-data") {
            return docs.appendingPathComponent("Lists-Attachment-Samples-V2", isDirectory: true)
        }
        #endif
        return docs.appendingPathComponent("Lists", isDirectory: true)
    }
}
