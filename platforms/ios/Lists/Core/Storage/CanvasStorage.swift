import Foundation

public enum CanvasStorageError: Error, Equatable, LocalizedError, Sendable {
    case invalidPath
    case missingCanvas
    case missingNativeDocument
    case missingPreview

    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            "The canvas path is invalid."
        case .missingCanvas:
            "The canvas document could not be found."
        case .missingNativeDocument:
            "The editable canvas data could not be found."
        case .missingPreview:
            "The canvas preview could not be found."
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
        let resource = try availableCanvasResource(title: title)
        let canvasURL = try canvasURL(for: resource.canvasPath)
        try FileManager.default.createDirectory(
            at: canvasURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encodeCanvas(CanvasDocument()).write(to: canvasURL, options: .atomic)
        return resource
    }

    /// Selects a human-readable Canvas bundle name without overwriting any
    /// existing `.canvas`, `.paper`, or `.png` member. The current bundle may
    /// be preserved when its sanitized stem already matches the title.
    public func availableCanvasResource(
        title: String,
        preserving currentPath: String? = nil
    ) throws -> CanvasResource {
        try ensureRoot()
        let preserved = try currentPath.map { path -> CanvasResource in
            guard let resource = CanvasResource(canvasPath: path) else {
                throw CanvasStorageError.invalidPath
            }
            return resource
        }
        let base = Self.sanitize(title)
        if let preserved,
           ((preserved.canvasPath as NSString).deletingPathExtension as NSString)
            .lastPathComponent == base {
            return preserved
        }

        let preservedPaths = Set([
            preserved?.canvasPath,
            preserved?.nativeMarkupPath,
            preserved?.previewPath,
            preserved?.portablePreviewPath
        ].compactMap { $0 })
        var suffix = 1
        while true {
            let stem = suffix == 1 ? base : "\(base) (\(suffix))"
            guard let candidate = CanvasResource(canvasPath: "Canvases/\(stem).canvas") else {
                throw CanvasStorageError.invalidPath
            }
            let occupied = try [
                candidate.canvasPath,
                candidate.nativeMarkupPath,
                candidate.previewPath,
                candidate.portablePreviewPath
            ].contains { path in
                guard preservedPaths.contains(path) == false else { return false }
                return FileManager.default.fileExists(
                    atPath: try canvasURL(for: path).path
                )
            }
            if occupied == false { return candidate }
            suffix += 1
        }
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

    public func readCanvasPreviewData(at relativePath: String) throws -> Data {
        guard let resource = CanvasResource(canvasPath: relativePath) else {
            throw CanvasStorageError.invalidPath
        }
        let url = try canvasURL(for: resource.previewPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CanvasStorageError.missingPreview
        }
        return try Data(contentsOf: url)
    }

    /// Raster layer referenced by JSON Canvas. It deliberately excludes
    /// semantic cards, which are emitted as their own file/link nodes. Older
    /// development bundles fall back to the complete preview until resaved.
    public func readCanvasPortablePreviewData(at relativePath: String) throws -> Data {
        guard let resource = CanvasResource(canvasPath: relativePath) else {
            throw CanvasStorageError.invalidPath
        }
        let url = try canvasURL(for: resource.portablePreviewPath)
        if FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        return try readCanvasPreviewData(at: relativePath)
    }

    /// Reconstructs a safe native fallback from the dedicated drawing raster
    /// and Lists-owned semantic nodes. A complete preview is intentionally not
    /// accepted because it may already contain baked link cards.
    public func readCanvasPortableRecovery(
        at relativePath: String
    ) throws -> CanvasPortableRecovery {
        guard let resource = CanvasResource(canvasPath: relativePath) else {
            throw CanvasStorageError.invalidPath
        }
        let previewURL = try canvasURL(for: resource.portablePreviewPath)
        guard FileManager.default.fileExists(atPath: previewURL.path) else {
            throw CanvasStorageError.missingPreview
        }
        let document = try readCanvasDocument(at: relativePath)
        return CanvasPortableRecovery(
            previewPNGData: try Data(contentsOf: previewURL),
            linkCards: document.nodes.compactMap(Self.linkCard)
        )
    }

    /// Saves the native PaperKit authoring model, complete in-app preview, and
    /// drawing-only portable preview. JSON Canvas references the latter because
    /// semantic cards are emitted as their own file/link nodes.
    public func writeCanvas(
        at relativePath: String,
        preservingDocumentFrom sourceRelativePath: String? = nil,
        nativeData: Data,
        previewPNGData: Data,
        portablePreviewPNGData: Data? = nil,
        linkCards: [CanvasLinkCard] = []
    ) throws {
        guard nativeData.isEmpty == false, previewPNGData.isEmpty == false,
              portablePreviewPNGData?.isEmpty != true,
              let resource = CanvasResource(canvasPath: relativePath) else {
            throw CanvasStorageError.invalidPath
        }

        let documentURL = try canvasURL(for: resource.canvasPath)
        let nativeURL = try canvasURL(for: resource.nativeMarkupPath)
        let previewURL = try canvasURL(for: resource.previewPath)
        let portablePreviewURL = try canvasURL(for: resource.portablePreviewPath)
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
        } else if let sourceRelativePath {
            let sourceURL = try canvasURL(for: sourceRelativePath)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                document = try JSONDecoder().decode(
                    CanvasDocument.self,
                    from: Data(contentsOf: sourceURL)
                )
            } else {
                document = CanvasDocument()
            }
        } else {
            document = CanvasDocument()
        }

        let previewFileName = portablePreviewURL.lastPathComponent
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
        try (portablePreviewPNGData ?? previewPNGData).write(
            to: portablePreviewURL,
            options: .atomic
        )
        try encodeCanvas(document).write(to: documentURL, options: .atomic)
    }

    public func deleteCanvasResource(at relativePath: String) throws {
        guard let resource = CanvasResource(canvasPath: relativePath) else {
            throw CanvasStorageError.invalidPath
        }
        for path in [
            resource.canvasPath,
            resource.nativeMarkupPath,
            resource.previewPath,
            resource.portablePreviewPath
        ] {
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
        let x = Double(integerPixel(card.x - card.width / 2))
        let y = Double(integerPixel(card.y - card.height / 2))
        let width = Double(max(1, integerPixel(card.width)))
        let height = Double(max(1, integerPixel(card.height)))
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
                width: width,
                height: height,
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
            width: width,
            height: height,
            url: card.destination,
            label: card.title
        )
    }

    private static func linkCard(for node: CanvasNode) -> CanvasLinkCard? {
        let prefix = "lists-link-"
        guard node.id.hasPrefix(prefix),
              let id = UUID(uuidString: String(node.id.dropFirst(prefix.count))),
              node.width > 0,
              node.height > 0 else { return nil }

        let destination: String
        let fallbackTitle: String
        switch node.type {
        case .link:
            guard let url = node.url?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty else { return nil }
            destination = url
            fallbackTitle = URL(string: url)?.host ?? url
        case .file:
            guard let file = node.file?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty else { return nil }
            let path = file
                .split(separator: "/", omittingEmptySubsequences: true)
                .map { percentEncodedPathComponent(String($0)) }
                .joined(separator: "/")
            guard path.isEmpty == false else { return nil }
            let fragment = node.subpath?
                .drop(while: { $0 == "#" })
                .trimmingCharacters(in: .whitespacesAndNewlines)
            destination = "/\(path)" + (fragment?.nilIfEmpty.map {
                "#\(percentEncodedFragment($0))"
            } ?? "")
            fallbackTitle = ((file as NSString).lastPathComponent as NSString)
                .deletingPathExtension
        case .text, .group:
            return nil
        }

        return CanvasLinkCard(
            id: id,
            title: node.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? fallbackTitle,
            destination: destination,
            x: node.x + node.width / 2,
            y: node.y + node.height / 2,
            width: node.width,
            height: node.height
        )
    }

    private static func integerPixel(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(exactly: value.rounded()) ?? 0
    }

    private static func percentEncodedPathComponent(_ component: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/#?%()")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }

    private static func percentEncodedFragment(_ fragment: String) -> String {
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.remove(charactersIn: "#%")
        return fragment.addingPercentEncoding(withAllowedCharacters: allowed) ?? fragment
    }
}
