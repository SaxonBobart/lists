import Foundation

public enum CanvasStorageError: Error, Equatable, LocalizedError, Sendable {
    case invalidPath
    case missingCanvas
    case missingNativeDocument

    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            "The canvas path is invalid."
        case .missingCanvas:
            "The canvas document could not be found."
        case .missingNativeDocument:
            "The editable canvas data could not be found."
        }
    }
}

extension FileStore {
    private static let nativePreviewNodeID = "lists-native-canvas-preview"

    @discardableResult
    public func createCanvasResource(title: String) throws -> CanvasResource {
        try ensureRoot()
        let directory = root.appendingPathComponent("Canvases", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let base = Self.sanitize(title)
        var suffix = 1
        var canvasURL: URL
        repeat {
            let stem = suffix == 1 ? base : "\(base) (\(suffix))"
            canvasURL = directory.appendingPathComponent("\(stem).canvas")
            suffix += 1
        } while FileManager.default.fileExists(atPath: canvasURL.path)
        guard let resource = CanvasResource(canvasPath: "Canvases/\(canvasURL.lastPathComponent)") else {
            throw CanvasStorageError.invalidPath
        }
        try FileManager.default.createDirectory(
            at: canvasURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encodeCanvas(CanvasDocument()).write(to: canvasURL, options: .atomic)
        return resource
    }

    public func readCanvasDocument(at relativePath: String) throws -> CanvasDocument {
        let url = try canvasURL(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CanvasStorageError.missingCanvas
        }
        return try JSONDecoder().decode(CanvasDocument.self, from: Data(contentsOf: url))
    }

    public func readNativeCanvasData(at relativePath: String) throws -> Data {
        guard let resource = CanvasResource(canvasPath: relativePath) else {
            throw CanvasStorageError.invalidPath
        }
        let url = try canvasURL(for: resource.nativeMarkupPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CanvasStorageError.missingNativeDocument
        }
        return try Data(contentsOf: url)
    }

    public func canvasPreviewURL(at relativePath: String) throws -> URL? {
        guard let resource = CanvasResource(canvasPath: relativePath) else {
            throw CanvasStorageError.invalidPath
        }
        let url = try canvasURL(for: resource.previewPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Saves the native PaperKit authoring model and a portable preview. The
    /// preview is represented as a standard JSON Canvas file node, allowing
    /// other canvas tools to display the page even before they gain an ink
    /// adapter for Lists' native layer.
    public func writeCanvas(
        at relativePath: String,
        nativeData: Data,
        previewPNGData: Data,
        linkCards: [CanvasLinkCard] = []
    ) throws {
        guard nativeData.isEmpty == false, previewPNGData.isEmpty == false,
              let resource = CanvasResource(canvasPath: relativePath) else {
            throw CanvasStorageError.invalidPath
        }

        let documentURL = try canvasURL(for: resource.canvasPath)
        let nativeURL = try canvasURL(for: resource.nativeMarkupPath)
        let previewURL = try canvasURL(for: resource.previewPath)
        try FileManager.default.createDirectory(
            at: documentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var document: CanvasDocument
        if FileManager.default.fileExists(atPath: documentURL.path) {
            document = try JSONDecoder().decode(
                CanvasDocument.self,
                from: Data(contentsOf: documentURL)
            )
        } else {
            document = CanvasDocument()
        }

        let previewFileName = previewURL.lastPathComponent
        if let index = document.nodes.firstIndex(where: { $0.id == Self.nativePreviewNodeID }) {
            document.nodes[index].file = previewFileName
        } else {
            document.nodes.insert(
                CanvasNode(
                    id: Self.nativePreviewNodeID,
                    type: .file,
                    x: 0,
                    y: 0,
                    width: 1_024,
                    height: 1_365,
                    file: previewFileName
                ),
                at: 0
            )
        }

        document.nodes.removeAll { $0.id.hasPrefix("lists-link-") }
        document.nodes.append(contentsOf: linkCards.map(Self.portableNode))

        try nativeData.write(to: nativeURL, options: .atomic)
        try previewPNGData.write(to: previewURL, options: .atomic)
        try encodeCanvas(document).write(to: documentURL, options: .atomic)
    }

    public func deleteCanvasResource(at relativePath: String) throws {
        guard let resource = CanvasResource(canvasPath: relativePath) else {
            throw CanvasStorageError.invalidPath
        }
        for path in [resource.canvasPath, resource.nativeMarkupPath, resource.previewPath] {
            let url = try canvasURL(for: path)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func canvasURL(for relativePath: String) throws -> URL {
        let relative = relativePath as NSString
        guard relative.isAbsolutePath == false,
              relativePath.contains("..") == false,
              relativePath.hasPrefix("Canvases/") else {
            throw CanvasStorageError.invalidPath
        }
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw CanvasStorageError.invalidPath
        }
        return candidate
    }

    private func encodeCanvas(_ document: CanvasDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    private static func portableNode(for card: CanvasLinkCard) -> CanvasNode {
        let nodeID = "lists-link-\(card.id.uuidString.lowercased())"
        let x = card.x - card.width / 2
        let y = card.y - card.height / 2
        if card.destination.hasPrefix("/") {
            let pieces = card.destination.split(
                separator: "#",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            let rawPath = String(pieces[0]).drop(while: { $0 == "/" })
            let file = String(rawPath).removingPercentEncoding ?? String(rawPath)
            let subpath = pieces.count == 2
                ? "#\(String(pieces[1]).removingPercentEncoding ?? String(pieces[1]))"
                : nil
            return CanvasNode(
                id: nodeID,
                type: .file,
                x: x,
                y: y,
                width: card.width,
                height: card.height,
                file: file,
                subpath: subpath,
                label: card.title
            )
        }
        return CanvasNode(
            id: nodeID,
            type: .link,
            x: x,
            y: y,
            width: card.width,
            height: card.height,
            url: card.destination,
            label: card.title
        )
    }
}
