import CryptoKit
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

    public func readCanvasLinkCards(at relativePath: String) throws -> [CanvasLinkCard] {
        try readCanvasDocument(at: relativePath).nodes.compactMap(Self.linkCard)
    }

    public func readCanvasTextCards(at relativePath: String) throws -> [CanvasTextCard] {
        try readCanvasDocument(at: relativePath).nodes.compactMap(Self.textCard)
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
            linkCards: document.nodes.compactMap(Self.linkCard),
            textCards: document.nodes.compactMap(Self.textCard),
            edges: document.edges
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
        linkCards: [CanvasLinkCard] = [],
        textCards: [CanvasTextCard] = [],
        edges: [CanvasEdge]? = nil
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

        document.nodes.removeAll(where: Self.isManagedSemanticCardNode)
        document.nodes.append(contentsOf: linkCards.map(Self.portableNode))
        document.nodes.append(contentsOf: textCards.map(Self.portableNode))
        if let edges {
            document.edges = edges
        }
        let retainedNodeIDs = Set(document.nodes.map(\.id))
        document.edges.removeAll {
            retainedNodeIDs.contains($0.fromNode) == false
                || retainedNodeIDs.contains($0.toNode) == false
        }

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
        let nodeID = card.canvasNodeID
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
                color: card.color,
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
            color: card.color,
            url: card.destination,
            label: card.title
        )
    }

    private static func portableNode(for card: CanvasTextCard) -> CanvasNode {
        CanvasNode(
            id: card.canvasNodeID,
            type: .text,
            x: Double(integerPixel(card.x - card.width / 2)),
            y: Double(integerPixel(card.y - card.height / 2)),
            width: Double(max(1, integerPixel(card.width))),
            height: Double(max(1, integerPixel(card.height))),
            color: card.color,
            text: card.markdown
        )
    }

    private static func linkCard(for node: CanvasNode) -> CanvasLinkCard? {
        let prefix = "lists-link-"
        let listsID = node.id.hasPrefix(prefix)
            ? UUID(uuidString: String(node.id.dropFirst(prefix.count)))
            : nil
        guard node.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
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
            let pathExtension = (file as NSString).pathExtension.lowercased()
            guard pathExtension == "md" || pathExtension == "canvas" else { return nil }
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
            id: listsID ?? UUID(uuidString: node.id) ?? stableUUID(for: node.id),
            portableNodeID: listsID == nil ? node.id : nil,
            title: node.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? fallbackTitle,
            destination: destination,
            color: node.color,
            x: node.x + node.width / 2,
            y: node.y + node.height / 2,
            width: node.width,
            height: node.height
        )
    }

    private static func textCard(for node: CanvasNode) -> CanvasTextCard? {
        let prefix = "lists-text-"
        let listsID = node.id.hasPrefix(prefix)
            ? UUID(uuidString: String(node.id.dropFirst(prefix.count)))
            : nil
        guard node.type == .text,
              node.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              node.width > 0,
              node.height > 0,
              let markdown = node.text else { return nil }
        return CanvasTextCard(
            id: listsID ?? UUID(uuidString: node.id) ?? stableUUID(for: node.id),
            portableNodeID: listsID == nil ? node.id : nil,
            markdown: markdown,
            color: node.color,
            x: node.x + node.width / 2,
            y: node.y + node.height / 2,
            width: node.width,
            height: node.height
        )
    }

    /// Keeps native adornment identity stable for JSON Canvas implementations
    /// whose node identifiers are arbitrary strings rather than UUIDs.
    private static func stableUUID(for identifier: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(identifier.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func isManagedSemanticCardNode(_ node: CanvasNode) -> Bool {
        switch node.type {
        case .link:
            return node.url?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty != nil
        case .file:
            guard let file = node.file?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty else { return false }
            let pathExtension = (file as NSString).pathExtension.lowercased()
            return pathExtension == "md" || pathExtension == "canvas"
        case .text:
            return node.text != nil
        case .group:
            return false
        }
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
