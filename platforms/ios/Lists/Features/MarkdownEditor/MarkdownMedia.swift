import SwiftUI
import UIKit
import AVKit
import ImageIO
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
        if isImage { return .image }
        let ext = URL(fileURLWithPath: path).pathExtension
        let type = UTType(filenameExtension: ext)
        if type?.conforms(to: .movie) == true { return .video }
        if type?.conforms(to: .audio) == true { return .audio }
        if type?.conforms(to: .pdf) == true { return .pdf }
        return .file
    }
    enum Kind { case image, video, audio, pdf, file }
    var height: CGFloat { height(for: 320) }

    func height(for width: CGFloat) -> CGFloat {
        guard isImage else { return 52 }
        guard let url else { return 220 }
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
        guard let regex = try? NSRegularExpression(pattern: #"(!?)\[((?:\\.|[^\]\\\n])*)\]\(((?:\.\./)*Attachments/[^)\n]+)\)"#) else { return [] }
        let ns = source as NSString
        return regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let path = ns.substring(with: match.range(at: 3))
            guard MarkdownAttachmentIndex.isSafeRelativePath(path) else { return nil }
            return Self(range: match.range, destinationRange: match.range(at: 3), label: ns.substring(with: match.range(at: 2)), path: path, isImage: match.range(at: 1).length > 0)
        }
    }
    static func block(in line: String) -> Self? {
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

struct MarkdownMediaCard: View {
    let reference: MarkdownMediaReference
    var onEditSource: (() -> Void)?
    var onRemove: (() -> Void)?
    var onReplace: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onToggleImage: (() -> Void)?
    @State private var thumbnail: UIImage?
    @State private var failure: String?
    @State private var preview: URL?
    @State private var showingFailure = false
    @State private var showingName = false
    @State private var displayName = ""

    private var title: String { reference.label.isEmpty ? URL(fileURLWithPath: reference.path).lastPathComponent : reference.label }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                if reference.isImage, let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFit()
                        .clipShape(.rect(cornerRadius: 10))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: failure == nil ? "paperclip" : "exclamationmark.circle")
                            .font(.callout).accessibilityHidden(true)
                        Text(title).font(.body).lineLimit(1).truncationMode(.middle)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(Color(.secondarySystemBackground).opacity(0.65), in: .rect(cornerRadius: 8))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel(title)
            .accessibilityHint("Opens attachment. Touch and hold for actions.")
            .accessibilityIdentifier("markdown.media.open.\(reference.id)")
            .contextMenu { attachmentActions }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Description", isPresented: $showingName) {
            TextField("Description", text: $displayName).accessibilityIdentifier("markdown.media.description")
            Button("Save") { onRename?(displayName) }.accessibilityIdentifier("markdown.media.description.save")
            Button("Cancel", role: .cancel) {}.accessibilityIdentifier("markdown.media.description.cancel")
        }
        .alert("Unable to Open Attachment", isPresented: $showingFailure) {
            Button("OK", role: .cancel) {}.accessibilityIdentifier("markdown.media.error.dismiss")
        } message: { Text(failure ?? "The file is unavailable.") }
        .quickLookPreview($preview)
        .task(id: reference.path + (MarkdownAudioRecording.shared.session?.fileName ?? "")) { await loadImage() }
        .accessibilityIdentifier("markdown.media.\(reference.id)")
    }

    @ViewBuilder private var attachmentActions: some View {
        Button("Open", systemImage: "arrow.up.right.square", action: open)
            .accessibilityIdentifier("markdown.media.action.open.\(reference.id)")
        if let url = reference.url {
            ShareLink(item: url).accessibilityIdentifier("markdown.media.share.\(reference.id)")
        }
        if let onToggleImage {
            Button(reference.isImage ? "Show as Link" : "Show Image", systemImage: reference.isImage ? "link" : "photo", action: onToggleImage)
                .accessibilityIdentifier("markdown.media.toggle.image.\(reference.id)")
        }
        if onRename != nil {
            Button("Edit Description", systemImage: "pencil") { displayName = title; showingName = true }
                .accessibilityIdentifier("markdown.media.rename.\(reference.id)")
        }
        if let onReplace { Button("Replace", systemImage: "arrow.triangle.2.circlepath", action: onReplace).accessibilityIdentifier("markdown.media.replace.\(reference.id)") }
        if let onCopy { Button("Copy", systemImage: "doc.on.doc", action: onCopy).accessibilityIdentifier("markdown.media.copy.\(reference.id)") }
        if let onCut { Button("Cut", systemImage: "scissors", action: onCut).accessibilityIdentifier("markdown.media.cut.\(reference.id)") }
        if let onEditSource { Button("Edit Source", systemImage: "chevron.left.forwardslash.chevron.right", action: onEditSource).accessibilityIdentifier("markdown.media.source.\(reference.id)") }
        if let onRemove { Button("Remove", systemImage: "trash", role: .destructive, action: onRemove).accessibilityIdentifier("markdown.media.remove.\(reference.id)") }
    }

    private func open() {
        guard let url = reference.url, FileManager.default.fileExists(atPath: url.path) else {
            failure = MarkdownAudioRecording.shared.session?.fileName == URL(fileURLWithPath: reference.path).lastPathComponent
                ? "Stop and save this recording before opening it."
                : "The attachment file could not be found. You can replace it or edit its Markdown link."
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
        guard reference.isImage else { return }
        guard let url = reference.url, FileManager.default.fileExists(atPath: url.path) else {
            failure = "The image file could not be found."
            return
        }
        let modification = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(url.path)|\(modification)" as NSString
        if let cached = MarkdownMediaThumbnails.cache.object(forKey: cacheKey) { thumbnail = cached; return }
        thumbnail = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { return nil as UIImage? }
            return UIImage(cgImage: image)
        }.value
        if let thumbnail {
            MarkdownMediaThumbnails.cache.setObject(thumbnail, forKey: cacheKey, cost: Int(thumbnail.size.width * thumbnail.size.height * thumbnail.scale * thumbnail.scale * 4))
        } else { failure = "The image could not be displayed. Tap to open the file." }
    }
}

@MainActor
final class MarkdownMediaOverlayController {
    private weak var textView: UITextView?
    private var views: [Int: UIHostingController<MarkdownMediaCard>] = [:]
    private var references: [Int: MarkdownMediaReference] = [:]
    private var refreshing = false
    var replace: ((String) -> Void)?
    var requestReplacement: ((NSRange) -> Void)?

    init(textView: UITextView) { self.textView = textView }
    func refresh() {
        guard !refreshing, let textView, let storage = textView.textStorage as? MarkdownStyler else { return }
        refreshing = true
        defer { refreshing = false }
        guard storage.mode == .live else {
            for view in views.values { view.view.removeFromSuperview() }
            views.removeAll(); references.removeAll(); MarkdownPlayback.shared.stop(); return
        }
        let ns = storage.string as NSString
        let refs = MarkdownMediaReference.references(in: storage.string).filter { ref in
            let line = ns.lineRange(for: ref.range)
            let literal = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
            return literal == ns.substring(with: ref.range) && storage.attribute(.markdownMediaBlock, at: ref.range.location, effectiveRange: nil) != nil
        }
        let ids = Set(refs.map(\.id))
        for id in Array(views.keys) where !ids.contains(id) { views.removeValue(forKey: id)?.view.removeFromSuperview(); references.removeValue(forKey: id) }
        for ref in refs {
            let glyphs = textView.layoutManager.glyphRange(forCharacterRange: ref.range, actualCharacterRange: nil)
            let bounds = textView.layoutManager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
            let frame = CGRect(x: textView.textContainerInset.left, y: bounds.minY + textView.textContainerInset.top + 4, width: max(1, textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right), height: (storage.mediaHeight(at: ref.range.location) ?? ref.height) - 8)
            if views[ref.id] == nil || references[ref.id] != ref {
                views.removeValue(forKey: ref.id)?.view.removeFromSuperview()
                let card = MarkdownMediaCard(reference: ref, onEditSource: { [weak self] in
                    self?.textView?.becomeFirstResponder(); self?.textView?.selectedRange = ref.range
                }, onRemove: { [weak self] in self?.edit(ref, replacement: "") }, onReplace: { [weak self] in self?.requestReplacement?(ref.range) }, onRename: { [weak self] label in
                    let source = "\(ref.isImage ? "!" : "")[\(DocumentMarkdownLinkBuilder.escapedLabel(label))](\(ref.path))"
                    self?.edit(ref, replacement: source)
                }, onCopy: { [weak self] in self?.copy(ref) }, onCut: { [weak self] in self?.copy(ref); self?.edit(ref, replacement: "") }, onToggleImage: UTType(filenameExtension: URL(fileURLWithPath: ref.path).pathExtension)?.conforms(to: .image) == true ? { [weak self] in
                    guard let self, let textView = self.textView, NSMaxRange(ref.range) <= textView.textStorage.length else { return }
                    let source = (textView.text as NSString).substring(with: ref.range)
                    self.edit(ref, replacement: ref.isImage ? String(source.dropFirst()) : "!" + source)
                } : nil)
                let host = UIHostingController(rootView: card)
                host.view.backgroundColor = .clear
                host.view.accessibilityIdentifier = "markdown.media.overlay.\(ref.id)"
                textView.addSubview(host.view)
                views[ref.id] = host; references[ref.id] = ref
            }
            views[ref.id]?.view.frame = frame
        }
    }
    private func copy(_ ref: MarkdownMediaReference) {
        guard let textView, NSMaxRange(ref.range) <= textView.textStorage.length else { return }
        UIPasteboard.general.string = (textView.text as NSString).substring(with: ref.range)
    }
    private func edit(_ ref: MarkdownMediaReference, replacement: String) {
        guard let textView, NSMaxRange(ref.range) <= textView.textStorage.length else { return }
        replace?((textView.text as NSString).replacingCharacters(in: ref.range, with: replacement))
    }
}
