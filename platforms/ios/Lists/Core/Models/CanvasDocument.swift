import Foundation

/// JSON Canvas 1.0 document.
///
/// Lists keeps this model deliberately independent from PaperKit. PaperKit is
/// the native iOS authoring surface; this file is the portable graph that an
/// Obsidian-compatible canvas tool can still inspect and extend.
public struct CanvasDocument: Codable, Equatable, Sendable {
    public var nodes: [CanvasNode]
    public var edges: [CanvasEdge]

    public init(nodes: [CanvasNode] = [], edges: [CanvasEdge] = []) {
        self.nodes = nodes
        self.edges = edges
    }
}

public struct CanvasNode: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case file
        case link
        case group
    }

    public var id: String
    public var type: Kind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var color: String?
    public var text: String?
    public var file: String?
    public var subpath: String?
    public var url: String?
    public var label: String?
    public var background: String?
    public var backgroundStyle: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        type: Kind,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        color: String? = nil,
        text: String? = nil,
        file: String? = nil,
        subpath: String? = nil,
        url: String? = nil,
        label: String? = nil,
        background: String? = nil,
        backgroundStyle: String? = nil
    ) {
        self.id = id
        self.type = type
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.color = color
        self.text = text
        self.file = file
        self.subpath = subpath
        self.url = url
        self.label = label
        self.background = background
        self.backgroundStyle = backgroundStyle
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case x
        case y
        case width
        case height
        case color
        case text
        case file
        case subpath
        case url
        case label
        case background
        case backgroundStyle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(Kind.self, forKey: .type)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        subpath = try container.decodeIfPresent(String.self, forKey: .subpath)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        background = try container.decodeIfPresent(String.self, forKey: .background)
        backgroundStyle = try container.decodeIfPresent(String.self, forKey: .backgroundStyle)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(Self.integerPixel(x), forKey: .x)
        try container.encode(Self.integerPixel(y), forKey: .y)
        try container.encode(max(1, Self.integerPixel(width)), forKey: .width)
        try container.encode(max(1, Self.integerPixel(height)), forKey: .height)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(file, forKey: .file)
        try container.encodeIfPresent(subpath, forKey: .subpath)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(background, forKey: .background)
        try container.encodeIfPresent(backgroundStyle, forKey: .backgroundStyle)
    }

    private static func integerPixel(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(exactly: value.rounded()) ?? 0
    }
}

/// The portable data needed to recover a readable Canvas when the native
/// PaperKit authoring sidecar is unavailable. The raster remains flattened;
/// semantic Lists link cards stay independently editable.
public struct CanvasPortableRecovery: Equatable, Sendable {
    public let previewPNGData: Data
    public let linkCards: [CanvasLinkCard]

    public init(previewPNGData: Data, linkCards: [CanvasLinkCard]) {
        self.previewPNGData = previewPNGData
        self.linkCards = linkCards
    }
}

public struct CanvasEdge: Codable, Equatable, Identifiable, Sendable {
    public enum Side: String, Codable, Sendable {
        case top
        case right
        case bottom
        case left
    }

    public enum End: String, Codable, Sendable {
        case none
        case arrow
    }

    public var id: String
    public var fromNode: String
    public var fromSide: Side?
    public var fromEnd: End?
    public var toNode: String
    public var toSide: Side?
    public var toEnd: End?
    public var color: String?
    public var label: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        fromNode: String,
        fromSide: Side? = nil,
        fromEnd: End? = nil,
        toNode: String,
        toSide: Side? = nil,
        toEnd: End? = .arrow,
        color: String? = nil,
        label: String? = nil
    ) {
        self.id = id
        self.fromNode = fromNode
        self.fromSide = fromSide
        self.fromEnd = fromEnd
        self.toNode = toNode
        self.toSide = toSide
        self.toEnd = toEnd
        self.color = color
        self.label = label
    }
}

/// A semantic, interactive link card authored on the native canvas.
///
/// PaperKit adornments provide the iOS presentation while these values keep
/// the link portable and stable in the JSON Canvas document.
public struct CanvasLinkCard: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var destination: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        id: UUID = UUID(),
        title: String,
        destination: String,
        x: Double,
        y: Double,
        width: Double = 360,
        height: Double = 88
    ) {
        self.id = id
        self.title = title
        self.destination = destination
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Stable group of files owned by one first-class Canvas item.
public struct CanvasResource: Equatable, Sendable {
    public let canvasPath: String
    public let nativeMarkupPath: String
    public let previewPath: String
    public let portablePreviewPath: String

    public init(itemID: UUID) {
        let stem = itemID.uuidString.lowercased()
        canvasPath = "Canvases/\(stem).canvas"
        nativeMarkupPath = "Canvases/\(stem).paper"
        previewPath = "Canvases/\(stem).png"
        portablePreviewPath = "Canvases/\(stem).drawing.png"
    }

    public init?(canvasPath: String) {
        let path = canvasPath as NSString
        guard path.pathExtension.lowercased() == "canvas",
              path.deletingLastPathComponent == "Canvases" else {
            return nil
        }
        let stem = (path.deletingPathExtension as NSString).lastPathComponent
        guard stem.isEmpty == false,
              stem != ".",
              stem != ".." else { return nil }
        self.canvasPath = canvasPath
        nativeMarkupPath = "Canvases/\(stem).paper"
        previewPath = "Canvases/\(stem).png"
        portablePreviewPath = "Canvases/\(stem).drawing.png"
    }
}
