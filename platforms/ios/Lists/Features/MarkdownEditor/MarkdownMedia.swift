import SwiftUI
import UIKit
import AVKit
import ImageIO
import PDFKit
import QuickLook
import UniformTypeIdentifiers

@MainActor private enum MarkdownMediaThumbnails {
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
}

struct MarkdownMediaReference: Identifiable, Equatable {
    let range: NSRange
    let destinationRange: NSRange
    let label: String
    let path: String
    let isImage: Bool
    var id: Int { range.location }
    var url: URL? { MarkdownAttachmentIndex.fileURL(path) }
    var kind: Kind {
        let ext = URL(fileURLWithPath: path).pathExtension
        let type = UTType(filenameExtension: ext)
        if type?.conforms(to: .image) == true { return .image }
        if type?.conforms(to: .movie) == true { return .video }
        if type?.conforms(to: .audio) == true { return .audio }
        if type?.conforms(to: .pdf) == true { return .pdf }
        return .file
    }
    enum Kind { case image, video, audio, pdf, file }
    var height: CGFloat { height(for: 320) }

    func height(for width: CGFloat) -> CGFloat {
        height(for: width, expanded: isImage || kind == .pdf)
    }

    var canPreview: Bool { kind == .image || kind == .pdf }

    func height(for width: CGFloat, expanded: Bool) -> CGFloat {
        guard expanded, canPreview else {
            return max(88, UIFont.preferredFont(forTextStyle: .body).lineHeight + UIFont.preferredFont(forTextStyle: .caption1).lineHeight + 38)
        }
        if kind == .pdf { return min(440, max(120, width * 1.3)) + 8 }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return 220 }
        // Read only image metadata; decoding remains in the asynchronous image loader.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              pixelWidth.doubleValue > 0, pixelHeight.doubleValue > 0 else { return 220 }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let ratio = CGFloat((5...8).contains(orientation)
            ? pixelWidth.doubleValue / pixelHeight.doubleValue
            : pixelHeight.doubleValue / pixelWidth.doubleValue)
        return max(52, max(1, width) * ratio + 8)
    }
    static func references(in source: String) -> [Self] {
        let ns = source as NSString
        let codeRanges = MarkdownFenceSyntax.blocks(in: source).map(\.fullRange)
            + MarkdownSyntax.inlineSpans(in: source).filter { $0.kind == .code }.map(\.fullRange)
        return MarkdownAttachmentIndex.referenceRegex.matches(in: source, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard !codeRanges.contains(where: { NSLocationInRange(match.range.location, $0) }) else { return nil }
            let path = ns.substring(with: match.range(at: 3))
            guard MarkdownAttachmentIndex.isSafeRelativePath(path) else { return nil }
            let label = displayLabel(ns.substring(with: match.range(at: 2)))
            return Self(range: match.range, destinationRange: match.range(at: 3), label: label, path: path, isImage: match.range(at: 1).length > 0)
        }
    }

    private static func displayLabel(_ source: String) -> String {
        var result = ""
        var escaped = false
        for character in source {
            if escaped {
                if character != "\\" && character != "[" && character != "]" { result.append("\\") }
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        if escaped { result.append("\\") }
        return result
    }
    static func block(in line: String) -> Self? {
        // Four spaces or a tab introduce an indented code example, not a card.
        guard !line.hasPrefix("    "), !line.hasPrefix("\t") else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ref = references(in: trimmed).first, ref.range.length == (trimmed as NSString).length else { return nil }
        return ref
    }
}

@MainActor @Observable
final class MarkdownPlayback {
    static let shared = MarkdownPlayback()
    @ObservationIgnored private weak var current: AVPlayer?
    @discardableResult func play(_ player: AVPlayer) -> Bool {
        guard claim(player) else { return false }
        player.play()
        return true
    }
    @discardableResult func claim(_ player: AVPlayer) -> Bool {
        guard MarkdownAudioRecording.shared.session == nil else {
            MarkdownAudioRecording.shared.message = "Stop and save the recording before playing other media."
            player.pause()
            return false
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        if current !== player { current?.pause(); current = player }
        return true
    }
    func stop() { current?.pause(); current = nil }
}

/// A device-local preference. The managed filename is stable when its document moves.
struct MarkdownAttachmentPresentation {
    let documentID: UUID?
    var defaults: UserDefaults = .standard

    func key(for reference: MarkdownMediaReference) -> String? {
        guard let documentID else { return nil }
        let filename = URL(fileURLWithPath: reference.path).lastPathComponent
        return "markdown.preview.v1.\(documentID.uuidString).\(filename)"
    }
    func isExpanded(_ reference: MarkdownMediaReference) -> Bool {
        guard reference.canPreview else { return false }
        guard let key = key(for: reference), defaults.object(forKey: key) != nil else {
            return reference.isImage || reference.kind == .pdf
        }
        return defaults.bool(forKey: key)
    }
    func setExpanded(_ expanded: Bool, for reference: MarkdownMediaReference) {
        guard let key = key(for: reference) else { return }
        defaults.set(expanded, forKey: key)
    }
}

/// Source-only transforms shared by deletion, selection and cursor navigation.
enum MarkdownAttachmentEditing {
    static func blocks(in source: String) -> [MarkdownMediaReference] {
        let ns = source as NSString
        return MarkdownMediaReference.references(in: source).filter {
            MarkdownMediaReference.block(in: ns.substring(with: ns.lineRange(for: $0.range))) != nil
        }
    }
    static func expandedRange(_ range: NSRange, in source: String) -> NSRange {
        guard range.length > 0 else { return range }
        return blocks(in: source).reduce(range) { result, block in
            NSIntersectionRange(result, block.range).length > 0 ? NSUnionRange(result, block.range) : result
        }
    }
    static func snappedCaret(_ location: Int, previous: Int, in source: String) -> Int {
        guard let block = blocks(in: source).first(where: {
            location > $0.range.location && location < NSMaxRange($0.range)
        }) else { return location }
        return location >= previous ? NSMaxRange(block.range) : block.range.location
    }
}

struct MarkdownMediaCard: View {
    let reference: MarkdownMediaReference
    var expanded: Bool? = nil
    var onTap: ((CGFloat) -> Bool)? = nil
    var onTogglePreview: (() -> Void)? = nil
    @State private var thumbnail: UIImage?
    @State private var failure: String?
    @State private var preview: URL?
    @State private var showingFailure = false

    private var showsPreview: Bool { expanded ?? (reference.isImage || reference.kind == .pdf) }
    private var title: String { reference.label.isEmpty ? URL(fileURLWithPath: reference.path).lastPathComponent : reference.label }
    private var metadata: String {
        guard let url = reference.url,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return "File unavailable" }
        var parts: [String] = []
        if let size = values.fileSize { parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
        if let date = values.contentModificationDate { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " · ")
    }
    private var typeLabel: String { URL(fileURLWithPath: reference.path).pathExtension.uppercased() }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture(coordinateSpace: .local) { point in
                if onTap?(point.x) != true { open() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(typeLabel + ", " + metadata)
            .accessibilityHint("While editing, places the cursor beside the attachment. Otherwise opens it.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if onTap?(.greatestFiniteMagnitude) != true { open() } }
            .accessibilityIdentifier("markdown.media.open.\(reference.id)")
            .contextMenu {
                Button("Open", systemImage: "arrow.up.right.square", action: open)
                    .accessibilityIdentifier("markdown.media.action.open.\(reference.id)")
                if reference.canPreview, let onTogglePreview {
                    Button(showsPreview ? "Hide Preview" : "Show Preview", systemImage: showsPreview ? "rectangle.compress.vertical" : "rectangle.expand.vertical", action: onTogglePreview)
                        .accessibilityIdentifier("markdown.media.toggle.preview.\(reference.id)")
                }
            } preview: {
                content.frame(width: 300, height: reference.height(for: 300, expanded: showsPreview) - 8)
            }
            .alert("Unable to Open Attachment", isPresented: $showingFailure) {
                Button("OK", role: .cancel) {}.accessibilityIdentifier("markdown.media.error.dismiss")
            } message: { Text(failure ?? "The file is unavailable.") }
            .quickLookPreview($preview)
            .task(id: reference.path + "|\(showsPreview)") { await loadImage() }
    }

    @ViewBuilder private var content: some View {
        if showsPreview, let thumbnail {
            Image(uiImage: thumbnail).resizable().scaledToFit()
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    if reference.kind == .pdf {
                        Text("PDF").font(.caption.weight(.semibold)).padding(6)
                            .background(.regularMaterial, in: Capsule()).padding(8)
                    }
                }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.body).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(typeLabel.isEmpty ? "FILE" : typeLabel).font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    Text(failure ?? metadata).font(.caption).lineLimit(1)
                }.foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)) }
        }
    }

    private func open() {
        guard let url = reference.url, FileManager.default.fileExists(atPath: url.path) else {
            failure = "The attachment file could not be found. Its Markdown reference is still available."
            showingFailure = true
            return
        }
        if (reference.kind == .audio || reference.kind == .video), MarkdownAudioRecording.shared.session != nil {
            failure = "Stop and save the current recording before playing other media."
            showingFailure = true
            return
        }
        failure = nil
        MarkdownPlayback.shared.stop()
        preview = url
    }

    private func loadImage() async {
        thumbnail = nil
        failure = nil
        guard showsPreview, reference.canPreview else { return }
        guard let url = reference.url, FileManager.default.fileExists(atPath: url.path) else {
            failure = "File unavailable"
            return
        }
        let modification = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(url.path)|\(modification)" as NSString
        if let cached = MarkdownMediaThumbnails.cache.object(forKey: cacheKey) { thumbnail = cached; return }
        let isPDF = reference.kind == .pdf
        let image = await Task.detached(priority: .utility) {
            if isPDF {
                return PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 1000, height: 1300), for: .cropBox)
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { return nil as UIImage? }
            return UIImage(cgImage: image)
        }.value
        guard !Task.isCancelled else { return }
        thumbnail = image
        if let thumbnail {
            MarkdownMediaThumbnails.cache.setObject(thumbnail, forKey: cacheKey, cost: Int(thumbnail.size.width * thumbnail.size.height * thumbnail.scale * thumbnail.scale * 4))
        } else { failure = "Preview unavailable" }
    }
}

@MainActor
final class MarkdownMediaOverlayController {
    private weak var textView: UITextView?
    private var views: [Int: UIHostingController<MarkdownMediaCard>] = [:]
    private var references: [Int: MarkdownMediaReference] = [:]
    private var expandedStates: [Int: Bool] = [:]
    private var refreshing = false

    init(textView: UITextView) { self.textView = textView }

    func refresh() {
        guard !refreshing, let textView, let storage = textView.textStorage as? MarkdownStyler else { return }
        refreshing = true
        defer { refreshing = false }
        let refs = storage.mode == .live ? MarkdownAttachmentEditing.blocks(in: storage.string) : []
        let ids = Set(refs.map(\.id))
        for id in Array(views.keys) where !ids.contains(id) {
            views.removeValue(forKey: id)?.view.removeFromSuperview()
            references.removeValue(forKey: id); expandedStates.removeValue(forKey: id)
        }
        let preferences = MarkdownAttachmentPresentation(documentID: storage.documentID)
        for ref in refs {
            guard let height = storage.mediaHeight(at: ref.range.location) else { continue }
            let glyph = textView.layoutManager.glyphIndexForCharacter(at: ref.range.location)
            let bounds = textView.layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let frame = CGRect(x: textView.textContainerInset.left, y: bounds.minY + textView.textContainerInset.top + 4, width: max(1, textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right - 4), height: height - 8)
            let expanded = preferences.isExpanded(ref)
            if views[ref.id] == nil || references[ref.id] != ref || expandedStates[ref.id] != expanded {
                let card = MarkdownMediaCard(reference: ref, expanded: expanded, onTap: { [weak textView] x in
                    guard let textView, textView.isMarkdownEditingActive else { return false }
                    textView.becomeFirstResponder()
                    let width = textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right
                    textView.selectedRange = NSRange(location: x < width / 2 ? ref.range.location : NSMaxRange(ref.range), length: 0)
                    textView.delegate?.textViewDidChangeSelection?(textView)
                    return true
                }, onTogglePreview: { [weak self, weak storage, weak textView] in
                    preferences.setExpanded(!preferences.isExpanded(ref), for: ref)
                    storage?.invalidateLayoutDependentStyling()
                    textView?.invalidateIntrinsicContentSize(); textView?.setNeedsLayout()
                    self?.refresh()
                })
                if let host = views[ref.id] { host.rootView = card }
                else {
                    let host = UIHostingController(rootView: card)
                    host.view.backgroundColor = .clear
                    host.view.accessibilityIdentifier = "markdown.media.overlay.\(ref.id)"
                    textView.addSubview(host.view); views[ref.id] = host
                }
                references[ref.id] = ref; expandedStates[ref.id] = expanded
            }
            views[ref.id]?.view.frame = frame
        }
    }
}
