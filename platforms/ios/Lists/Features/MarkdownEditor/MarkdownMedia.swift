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
    var height: CGFloat {
        switch kind { case .image, .video: 220; case .audio: 100; case .pdf: 112; case .file: 76 }
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
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    @State private var failure: String?
    @State private var preview: URL?
    @State private var player: AVPlayer?
    @State private var playbackObservation: NSKeyValueObservation?
    @State private var playing = false
    @State private var pageCount = 0
    @State private var duration = 0.0
    @State private var position = 0.0
    @State private var isSeeking = false
    @State private var showingName = false
    @State private var displayName = ""

    private var title: String { reference.label.isEmpty ? URL(fileURLWithPath: reference.path).lastPathComponent : reference.label }
    private var subtitle: String {
        let size = reference.url.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
        return (pageCount > 0 ? "\(pageCount) \(pageCount == 1 ? "page" : "pages") · " : "") + "\(URL(fileURLWithPath: reference.path).pathExtension.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle").font(.callout)
                Text(title).font(.caption).foregroundStyle(.secondary)
                if MarkdownAudioRecording.shared.session?.fileName != URL(fileURLWithPath: reference.path).lastPathComponent {
                    Button("Retry") { Task { await load() } }.accessibilityIdentifier("markdown.media.retry.\(reference.id)")
                }
            } else if isLoading {
                ProgressView("Loading \(title)")
            } else {
                mediaContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(reference.kind == .image || reference.kind == .video ? 0 : 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            Menu {
                if failure == nil, let url = reference.url {
                    Button("Open", systemImage: "arrow.up.right.square") { preview = url }.accessibilityIdentifier("markdown.media.open.\(reference.id)")
                    ShareLink(item: url).accessibilityIdentifier("markdown.media.share.\(reference.id)")
                }
                if let onRename {
                    Button("Edit Description", systemImage: "pencil") { displayName = title; showingName = true }
                        .accessibilityIdentifier("markdown.media.rename.\(reference.id)")
                    // Keeps the closure alive across the alert's presentation.
                    let _ = onRename
                }
                if let onReplace { Button("Replace", systemImage: "arrow.triangle.2.circlepath", action: onReplace).accessibilityIdentifier("markdown.media.replace.\(reference.id)") }
                if let onCopy { Button("Copy", systemImage: "doc.on.doc", action: onCopy).accessibilityIdentifier("markdown.media.copy.\(reference.id)") }
                if let onCut { Button("Cut", systemImage: "scissors", action: onCut).accessibilityIdentifier("markdown.media.cut.\(reference.id)") }
                if let onEditSource { Button("Edit Source", systemImage: "chevron.left.forwardslash.chevron.right", action: onEditSource).accessibilityIdentifier("markdown.media.source.\(reference.id)") }
                if let onRemove { Button("Remove", systemImage: "trash", role: .destructive, action: onRemove).accessibilityIdentifier("markdown.media.remove.\(reference.id)") }
            } label: { Image(systemName: "ellipsis").padding(10).background(.regularMaterial, in: Circle()) }
            .accessibilityLabel("Attachment actions").accessibilityIdentifier("markdown.media.menu.\(reference.id)").padding(6)
        }
        .alert("Description", isPresented: $showingName) {
            TextField("Description", text: $displayName).accessibilityIdentifier("markdown.media.description")
            Button("Save") { onRename?(displayName) }.accessibilityIdentifier("markdown.media.description.save")
            Button("Cancel", role: .cancel) {}.accessibilityIdentifier("markdown.media.description.cancel")
        }
        .quickLookPreview($preview)
        .onChange(of: preview) { if preview != nil { MarkdownPlayback.shared.stop() } }
        .task(id: reference.path + (MarkdownAudioRecording.shared.session?.fileName ?? "")) { await load() }
        .onDisappear { player?.pause(); playing = false }
        .accessibilityIdentifier("markdown.media.\(reference.id)")
    }

    @ViewBuilder private var mediaContent: some View {
        switch reference.kind {
        case .image:
            Button { preview = reference.url } label: {
                if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit() }
                else { Label(title, systemImage: "photo") }
            }.buttonStyle(.plain).accessibilityLabel(title).accessibilityIdentifier("markdown.media.image.\(reference.id)")
        case .video:
            if playing, let player {
                VideoPlayer(player: player).accessibilityIdentifier("markdown.media.video.\(reference.id)")
            } else {
                Button {
                    if let player { playing = MarkdownPlayback.shared.play(player) }
                } label: {
                    ZStack {
                        if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit() }
                        Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white).shadow(radius: 3)
                    }
                }.buttonStyle(.plain).accessibilityLabel("Play \(title)").accessibilityIdentifier("markdown.media.play.\(reference.id)")
            }
        case .audio:
            VStack(alignment: .leading) {
                Text(title).font(.headline).lineLimit(1).padding(.trailing, 35)
                HStack {
                    Button {
                        guard let player else { return }
                        if player.rate > 0 { player.pause(); playing = false }
                        else { playing = MarkdownPlayback.shared.play(player) }
                    } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 44, height: 32) }
                    .accessibilityLabel(playing ? "Pause" : "Play").accessibilityIdentifier("markdown.media.play.\(reference.id)")
                    Slider(value: $position, in: 0...max(duration, 1), onEditingChanged: { editing in
                        isSeeking = editing
                        if !editing { player?.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
                    }).accessibilityLabel("Playback position").accessibilityIdentifier("markdown.media.seek.\(reference.id)")
                    Text(Duration.seconds(position).formatted(.time(pattern: .minuteSecond))).font(.caption.monospacedDigit())
                }
            }.task {
                while !Task.isCancelled {
                    if let player, !isSeeking { position = max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0); playing = player.rate > 0 }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        case .pdf, .file:
            Button { preview = reference.url } label: {
                HStack(spacing: 12) {
                    if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit().frame(width: 60) }
                    else { Image(systemName: reference.kind == .pdf ? "doc.richtext" : "doc").font(.title2) }
                    VStack(alignment: .leading) { Text(title).font(.headline).lineLimit(2); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 32)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("markdown.media.file.\(reference.id)")
        }
    }

    private func load() async {
        isLoading = true; failure = nil; thumbnail = nil
        defer { isLoading = false }
        guard let url = reference.url, FileManager.default.fileExists(atPath: url.path) else { failure = MarkdownAudioRecording.shared.session?.fileName == URL(fileURLWithPath: reference.path).lastPathComponent ? "Recording in progress — use the recording controls to save" : "Attachment unavailable"; return }
        let modification = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(url.path)|\(modification)" as NSString
        let cachedThumbnail = MarkdownMediaThumbnails.cache.object(forKey: cacheKey)
        switch reference.kind {
        case .image:
            if let cachedThumbnail { thumbnail = cachedThumbnail; return }
            thumbnail = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { return nil as UIImage? }
                return UIImage(cgImage: image)
            }.value
            if thumbnail == nil { failure = "Image could not be opened" }
        case .audio, .video:
            let asset = AVURLAsset(url: url)
            do {
                guard try await asset.load(.isPlayable) else { failure = "This media format cannot be played"; return }
                duration = try await asset.load(.duration).seconds
                if !duration.isFinite { duration = 0 }
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                playbackObservation = player?.observe(\.rate, options: [.new]) { player, change in
                    guard (change.newValue ?? 0) > 0 else { return }
                    Task { @MainActor in MarkdownPlayback.shared.claim(player) }
                }
                if reference.kind == .video {
                    if let cachedThumbnail { thumbnail = cachedThumbnail; return }
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 1200, height: 800)
                    if let result = try? await generator.image(at: .zero) { thumbnail = UIImage(cgImage: result.image) }
                }
            } catch { failure = "Media could not be opened" }
        case .pdf:
            pageCount = CGPDFDocument(url as CFURL)?.numberOfPages ?? 0
            if let cachedThumbnail { thumbnail = cachedThumbnail; return }
            thumbnail = await Task.detached(priority: .utility) {
                guard let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: 1) else { return nil as UIImage? }
                let box = page.getBoxRect(.mediaBox)
                let size = CGSize(width: 160, height: 160 * box.height / max(box.width, 1))
                return UIGraphicsImageRenderer(size: size).image { context in
                    UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
                    context.cgContext.translateBy(x: 0, y: size.height)
                    context.cgContext.scaleBy(x: size.width / box.width, y: -size.height / box.height)
                    context.cgContext.drawPDFPage(page)
                }
            }.value
            if thumbnail == nil { failure = "PDF could not be opened" }
        case .file: break
        }
        if let thumbnail {
            MarkdownMediaThumbnails.cache.setObject(thumbnail, forKey: cacheKey, cost: Int(thumbnail.size.width * thumbnail.size.height * thumbnail.scale * thumbnail.scale * 4))
        }
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
            let frame = CGRect(x: textView.textContainerInset.left, y: bounds.minY + textView.textContainerInset.top + 4, width: max(1, textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right), height: ref.height - 8)
            if views[ref.id] == nil || references[ref.id] != ref {
                views.removeValue(forKey: ref.id)?.view.removeFromSuperview()
                let card = MarkdownMediaCard(reference: ref, onEditSource: { [weak self] in
                    self?.textView?.becomeFirstResponder(); self?.textView?.selectedRange = ref.range
                }, onRemove: { [weak self] in self?.edit(ref, replacement: "") }, onReplace: { [weak self] in self?.requestReplacement?(ref.range) }, onRename: { [weak self] label in
                    let source = "\(ref.isImage ? "!" : "")[\(DocumentMarkdownLinkBuilder.escapedLabel(label))](\(ref.path))"
                    self?.edit(ref, replacement: source)
                }, onCopy: { [weak self] in self?.copy(ref) }, onCut: { [weak self] in self?.copy(ref); self?.edit(ref, replacement: "") })
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
