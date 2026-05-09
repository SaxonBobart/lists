import Foundation

/// Resolves the on-disk root for the Lists library.
///
/// On iOS this is `<app sandbox>/Documents/Lists/` — app-private (NOT in
/// Files.app, NOT iCloud Drive). See `CLAUDE.md` for the storage policy.
public enum StorageRoot {
    public static func defaultListsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("Lists", isDirectory: true)
    }
}
