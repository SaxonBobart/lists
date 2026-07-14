import Foundation

public struct StoredAttachment: Equatable, Sendable {
    public let relativePath: String
    public let fileName: String
    public let byteCount: Int

    public var markdownDestination: String { relativePath }
}

public struct StoredDrawing: Equatable, Sendable {
    public let source: StoredAttachment
    public let preview: StoredAttachment
}

public enum AttachmentStorageError: Error, Equatable, LocalizedError, Sendable {
    case emptyData
    case invalidPath(String)
    case missingAttachment(String)
    case destinationExists(String)

    public var errorDescription: String? {
        switch self {
        case .emptyData:
            "The attachment is empty."
        case .invalidPath(let path):
            "The attachment path is invalid: \(path)"
        case .missingAttachment(let path):
            "The attachment could not be found: \(path)"
        case .destinationExists(let path):
            "An attachment already exists at: \(path)"
        }
    }
}

public enum MarkdownAttachmentIndex {
    public static func referencedPaths(in markdown: String) -> Set<String> {
        let ns = markdown as NSString
        let range = NSRange(location: 0, length: ns.length)
        let regex = try! NSRegularExpression(
            pattern: #"!?\[[^\]\n]*\]\((Attachments/[^)\n]+)\)"#
        )
        var paths: Set<String> = []
        regex.enumerateMatches(in: markdown, range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let raw = ns.substring(with: match.range(at: 1))
            let decoded = raw.removingPercentEncoding ?? raw
            if isSafeRelativePath(decoded) {
                paths.insert(decoded)
                if URL(fileURLWithPath: decoded).pathExtension.lowercased() == "png" {
                    paths.insert((decoded as NSString).deletingPathExtension + ".drawing")
                }
            }
        }
        return paths
    }

    public static func referencedPaths(in items: [Item]) -> Set<String> {
        items.reduce(into: Set<String>()) { result, item in
            result.formUnion(referencedPaths(in: item.body))
        }
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard path.hasPrefix("Attachments/"), path.hasPrefix("/") == false else { return false }
        let components = NSString(string: path).pathComponents
        return components.first == "Attachments"
            && components.count == 2
            && components.contains("..") == false
            && components.last?.isEmpty == false
    }
}

extension FileStore {
    private var attachmentsDirectory: URL {
        root.appendingPathComponent("Attachments", isDirectory: true)
    }

    private var attachmentTrashDirectory: URL {
        root.appendingPathComponent(".attachments-trash", isDirectory: true)
    }

    public func importAttachment(
        data: Data,
        originalFileName: String?,
        preferredExtension: String? = nil
    ) throws -> StoredAttachment {
        guard data.isEmpty == false else { throw AttachmentStorageError.emptyData }
        try ensureRoot()
        try FileManager.default.createDirectory(
            at: attachmentsDirectory,
            withIntermediateDirectories: true
        )

        let ext = sanitizedExtension(
            preferredExtension?.nilIfEmpty
                ?? originalFileName.map { URL(fileURLWithPath: $0).pathExtension }?.nilIfEmpty
                ?? "bin"
        )
        let fileName = "\(UUID().uuidString.lowercased()).\(ext)"
        let destination = attachmentsDirectory.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: destination, options: [.atomic])
        return StoredAttachment(
            relativePath: "Attachments/\(fileName)",
            fileName: fileName,
            byteCount: data.count
        )
    }

    public func importDrawing(sourceData: Data, previewPNGData: Data) throws -> StoredDrawing {
        guard sourceData.isEmpty == false, previewPNGData.isEmpty == false else {
            throw AttachmentStorageError.emptyData
        }
        try ensureRoot()
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let stem = UUID().uuidString.lowercased()
        let sourceName = "\(stem).drawing"
        let previewName = "\(stem).png"
        let sourceURL = attachmentsDirectory.appendingPathComponent(sourceName)
        let previewURL = attachmentsDirectory.appendingPathComponent(previewName)
        try sourceData.write(to: sourceURL, options: [.atomic])
        do {
            try previewPNGData.write(to: previewURL, options: [.atomic])
        } catch {
            try? FileManager.default.removeItem(at: sourceURL)
            throw error
        }
        return StoredDrawing(
            source: StoredAttachment(
                relativePath: "Attachments/\(sourceName)",
                fileName: sourceName,
                byteCount: sourceData.count
            ),
            preview: StoredAttachment(
                relativePath: "Attachments/\(previewName)",
                fileName: previewName,
                byteCount: previewPNGData.count
            )
        )
    }

    public func replaceDrawing(
        sourceRelativePath: String,
        previewRelativePath: String,
        sourceData: Data,
        previewPNGData: Data
    ) throws -> StoredDrawing {
        guard sourceData.isEmpty == false, previewPNGData.isEmpty == false else {
            throw AttachmentStorageError.emptyData
        }
        guard MarkdownAttachmentIndex.isSafeRelativePath(sourceRelativePath),
              MarkdownAttachmentIndex.isSafeRelativePath(previewRelativePath),
              URL(fileURLWithPath: sourceRelativePath).pathExtension.lowercased() == "drawing",
              URL(fileURLWithPath: previewRelativePath).pathExtension.lowercased() == "png",
              (sourceRelativePath as NSString).deletingPathExtension
                == (previewRelativePath as NSString).deletingPathExtension else {
            throw AttachmentStorageError.invalidPath(sourceRelativePath)
        }

        let sourceURL = try attachmentURL(for: sourceRelativePath)
        let previewURL = try attachmentURL(for: previewRelativePath)
        let previousSource = try Data(contentsOf: sourceURL)
        try sourceData.write(to: sourceURL, options: [.atomic])
        do {
            try previewPNGData.write(to: previewURL, options: [.atomic])
        } catch {
            try? previousSource.write(to: sourceURL, options: [.atomic])
            throw error
        }
        return StoredDrawing(
            source: StoredAttachment(
                relativePath: sourceRelativePath,
                fileName: sourceURL.lastPathComponent,
                byteCount: sourceData.count
            ),
            preview: StoredAttachment(
                relativePath: previewRelativePath,
                fileName: previewURL.lastPathComponent,
                byteCount: previewPNGData.count
            )
        )
    }

    public func attachmentURL(for relativePath: String) throws -> URL {
        guard MarkdownAttachmentIndex.isSafeRelativePath(relativePath) else {
            throw AttachmentStorageError.invalidPath(relativePath)
        }
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        let attachmentsRoot = attachmentsDirectory.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(attachmentsRoot) else {
            throw AttachmentStorageError.invalidPath(relativePath)
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw AttachmentStorageError.missingAttachment(relativePath)
        }
        return candidate
    }

    /// Moves unreferenced files aside rather than deleting them. The trash is
    /// included in full-library exports, so an over-eager cleanup remains
    /// recoverable even before the file is restored in-app.
    public func quarantineUnreferencedAttachments(
        referencedPaths: Set<String>
    ) throws -> [String] {
        guard FileManager.default.fileExists(atPath: attachmentsDirectory.path) else { return [] }
        try FileManager.default.createDirectory(
            at: attachmentTrashDirectory,
            withIntermediateDirectories: true
        )
        let urls = try FileManager.default.contentsOfDirectory(
            at: attachmentsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var quarantined: [String] = []
        for source in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relativePath = "Attachments/\(source.lastPathComponent)"
            guard referencedPaths.contains(relativePath) == false else { continue }
            let destination = attachmentTrashDirectory.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                throw AttachmentStorageError.destinationExists(source.lastPathComponent)
            }
            try FileManager.default.moveItem(at: source, to: destination)
            quarantined.append(relativePath)
        }
        return quarantined
    }

    public func restoreQuarantinedAttachment(fileName: String) throws -> StoredAttachment {
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        guard safeName == fileName, safeName.isEmpty == false else {
            throw AttachmentStorageError.invalidPath(fileName)
        }
        let source = attachmentTrashDirectory.appendingPathComponent(safeName)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw AttachmentStorageError.missingAttachment(fileName)
        }
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let destination = attachmentsDirectory.appendingPathComponent(safeName)
        guard FileManager.default.fileExists(atPath: destination.path) == false else {
            throw AttachmentStorageError.destinationExists("Attachments/\(safeName)")
        }
        try FileManager.default.moveItem(at: source, to: destination)
        let byteCount = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return StoredAttachment(
            relativePath: "Attachments/\(safeName)",
            fileName: safeName,
            byteCount: byteCount
        )
    }

    private func sanitizedExtension(_ raw: String) -> String {
        let allowed = raw.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        let value = String(String.UnicodeScalarView(allowed))
        return String(value.prefix(12)).nilIfEmpty ?? "bin"
    }
}
