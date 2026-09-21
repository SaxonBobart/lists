import UIKit
import WebKit

struct MarkdownRenderedSource: Equatable {
    let range: NSRange
    let source: String
    let kind: String
    let contentRange: NSRange
    init(range: NSRange, source: String, kind: String, contentRange: NSRange? = nil) {
        self.range = range; self.source = source; self.kind = kind
        self.contentRange = contentRange ?? range
    }
    func isEditing(_ selection: NSRange) -> Bool {
        guard selection.location != NSNotFound else { return false }
        if selection.length > 0 { return NSIntersectionRange(range, selection).length > 0 }
        return selection.location >= range.location && selection.location <= NSMaxRange(range)
    }
    static func spans(in source: String) -> [Self] {
        let ns = source as NSString
        var result: [Self] = []
        let patterns = [(#"(?m)^\$\$[ \t]*\n([\s\S]*?)\n\$\$[ \t]*$"#, "display"), (#"(?<![\\$])\$([^$\n]+)\$(?!\$)"#, "inline")]
        let fences = MarkdownFenceSyntax.blocks(in: source)
        let code = fences.map(\.fullRange)
        for fence in fences where fence.isClosed && fence.info.lowercased() == "mermaid" {
            var body = ns.substring(with: fence.contentRange)
            if body.hasSuffix("\n") { body.removeLast() }
            if body.hasSuffix("\r") { body.removeLast() }
            var range = fence.fullRange
            while range.length > 0, [10, 13].contains(Int(ns.character(at: NSMaxRange(range) - 1))) {
                range.length -= 1
            }
            result.append(Self(range: range, source: body, kind: "diagram", contentRange: NSRange(location: fence.contentRange.location, length: body.utf16.count)))
        }
        let inlineCode = (try? NSRegularExpression(pattern: #"(`+)[^\n]*?\1"#))?.matches(in: source, range: NSRange(location: 0, length: ns.length)).map(\.range) ?? []
        for (pattern, kind) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                if result.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) { continue }
                if kind != "diagram", (code + inlineCode).contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
                result.append(Self(range: match.range, source: ns.substring(with: match.range(at: 1)), kind: kind, contentRange: match.range(at: 1)))
            }
        }
        return result.sorted { $0.range.location < $1.range.location }
    }
}

final class MarkdownRenderedImage: NSObject {
    let image: UIImage
    let kind: String
    let source: String
    init(image: UIImage, kind: String, source: String) { self.image = image; self.kind = kind; self.source = source }
}

enum MarkdownSyntaxRenderState {
    case pending
    case success(MarkdownRenderedImage)
    case diagnostic(String)
}

@MainActor final class MarkdownSyntaxRenderer: NSObject, WKNavigationDelegate {
    static let shared = MarkdownSyntaxRenderer()
    private let webView: WKWebView
    private var loaded = false
    private var loadError: Error?
    private var queue: Task<Void, Never>?
    private let cache = NSCache<NSString, MarkdownRenderedImage>()
    private var failures: [String: String] = [:]
    private var latestRequest: [String: String] = [:]
    private var pending: Set<String> = []
    static let didRender = Notification.Name("ListsMarkdownSyntaxRendered")

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 1600), configuration: configuration)
        super.init()
        webView.isOpaque = false; webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false; webView.navigationDelegate = self
        cache.totalCostLimit = 32 * 1024 * 1024
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "EditorRenderers") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { loadError = CocoaError(.fileNoSuchFile) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loadError = error }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loadError = error }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.isFileURL == true ? .allow : .cancel
    }
    func key(_ span: MarkdownRenderedSource, width: CGFloat, fontSize: CGFloat, dark: Bool) -> String { "\(span.kind)|\(Int(width))|\(fontSize)|\(dark)|\(span.source)" }
    func result(_ span: MarkdownRenderedSource, width: CGFloat, fontSize: CGFloat, dark: Bool, coalescingID: String? = nil) -> MarkdownRenderedImage? {
        let key = key(span, width: width, fontSize: fontSize, dark: dark)
        if let coalescingID { latestRequest[coalescingID] = key }
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard !pending.contains(key), failures[key] == nil, width > 1 else { return nil }
        guard span.source.utf16.count <= 30000 else { failures[key] = "This block exceeds the 30,000-character preview limit."; return nil }
        pending.insert(key)
        let previous = queue
        queue = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                self.pending.remove(key)
                if let coalescingID, self.latestRequest[coalescingID] == key { self.latestRequest.removeValue(forKey: coalescingID) }
                NotificationCenter.default.post(name: Self.didRender, object: nil)
            }
            @MainActor func isCurrent() -> Bool { coalescingID.map { self.latestRequest[$0] == key } ?? true }
            guard isCurrent() else { return }
            do {
                try await Task.sleep(for: .milliseconds(100))
                guard isCurrent() else { return }
                for _ in 0..<100 where !self.loaded && self.loadError == nil { try await Task.sleep(for: .milliseconds(100)) }
                guard self.loaded else { throw self.loadError ?? CocoaError(.fileReadUnknown) }
                self.webView.frame.size = CGSize(width: width, height: 1600)
                let value = try await self.webView.callAsyncJavaScript("return await window.renderDocumentSyntax(source,kind,dark,size,width)", arguments: ["source": span.source, "kind": span.kind, "dark": dark, "size": fontSize, "width": width], in: nil, contentWorld: .page)
                guard isCurrent() else { return }
                guard let dimensions = value as? [String: Any] else { throw CocoaError(.coderInvalidValue) }
                if let message = dimensions["error"] as? String {
                    self.failures[key] = message
                    return
                }
                guard let w = dimensions["width"] as? Double, let h = dimensions["height"] as? Double, w > 0, h > 0 else { throw CocoaError(.coderInvalidValue) }
                let configuration = WKSnapshotConfiguration()
                configuration.rect = CGRect(x: 0, y: 0, width: w, height: h)
                let image = try await self.webView.takeSnapshot(configuration: configuration)
                guard isCurrent() else { return }
                let rendered = MarkdownRenderedImage(image: image, kind: span.kind, source: span.source)
                self.cache.setObject(rendered, forKey: key as NSString, cost: Int(w * h * image.scale * image.scale * 4))
            } catch { self.failures[key] = "Preview unavailable. " + error.localizedDescription }
        }
        return nil
    }
    func state(_ span: MarkdownRenderedSource, width: CGFloat, fontSize: CGFloat, dark: Bool, coalescingID: String? = nil) -> MarkdownSyntaxRenderState {
        if let image = result(span, width: width, fontSize: fontSize, dark: dark, coalescingID: coalescingID) { return .success(image) }
        if let message = failures[key(span, width: width, fontSize: fontSize, dark: dark)] { return .diagnostic(message) }
        return .pending
    }
    func failed(_ span: MarkdownRenderedSource, width: CGFloat, fontSize: CGFloat, dark: Bool) -> Bool {
        failures[key(span, width: width, fontSize: fontSize, dark: dark)] != nil
    }
}

import SwiftUI

struct RenderedSyntaxPreview: View {
    let source: String
    let kind: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var rendered: MarkdownRenderedImage?
    @State private var diagnostic: String?
    @State private var showingPreview = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let rendered {
                Button { showingPreview = true } label: {
                    Image(uiImage: rendered.image).resizable().scaledToFit()
                }.buttonStyle(.plain)
                    .accessibilityLabel(kind == "diagram" ? "Diagram: \(source)" : "Equation: \(source)")
                    .accessibilityIdentifier("markdown.rendered.preview")
            } else {
                if let diagnostic { Label(diagnostic, systemImage: "exclamationmark.triangle").font(.caption) }
                Text(source).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
        }
        .onAppear { refresh() }
        .onChange(of: source) { refresh() }
        .onChange(of: colorScheme) { refresh() }
        .onChange(of: dynamicTypeSize) { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: MarkdownSyntaxRenderer.didRender)) { _ in refresh() }
        .sheet(isPresented: $showingPreview) {
            if let rendered { RenderedSyntaxViewer(rendered: rendered) }
        }
    }
    private func refresh() {
        let span = MarkdownRenderedSource(range: NSRange(location: 0, length: source.utf16.count), source: source, kind: kind)
        let renderer = MarkdownSyntaxRenderer.shared
        switch renderer.state(span, width: 340, fontSize: UIFont.preferredFont(forTextStyle: .body).pointSize, dark: colorScheme == .dark) {
        case .success(let image): rendered = image; diagnostic = nil
        case .diagnostic(let message): rendered = nil; diagnostic = message
        case .pending: rendered = nil; diagnostic = nil
        }
    }
}

struct RenderedSyntaxViewer: View {
    let rendered: MarkdownRenderedImage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZoomableSyntaxImage(image: rendered.image)
                .accessibilityLabel(rendered.source)
                .navigationTitle(rendered.kind == "diagram" ? "Diagram" : "Equation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly).accessibilityIdentifier("markdown.rendered.done")
                } }
        }
    }
}

private struct ZoomableSyntaxImage: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 8
        scroll.delegate = context.coordinator
        let view = UIImageView(image: image)
        view.frame = CGRect(origin: CGPoint(x: 16, y: 16), size: image.size)
        scroll.addSubview(view); scroll.contentSize = CGSize(width: image.size.width + 32, height: image.size.height + 32)
        context.coordinator.imageView = view
        scroll.accessibilityIdentifier = "markdown.rendered.zoom"
        return scroll
    }
    func updateUIView(_ uiView: UIScrollView, context: Context) {}
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}

@MainActor final class MarkdownRenderedOverlayController {
    private weak var textView: UITextView?
    private var views: [Int: UIButton] = [:]
    init(textView: UITextView) { self.textView = textView }

    func refresh() {
        guard let view = textView, let storage = view.textStorage as? MarkdownStyler else { return }
        let spans = storage.mode == .live ? MarkdownRenderedSource.spans(in: storage.string).filter { $0.kind != "inline" } : []
        let ids = Set(spans.map { $0.range.location })
        for id in Array(views.keys) where !ids.contains(id) { views.removeValue(forKey: id)?.removeFromSuperview() }
        for span in spans {
            let key = span.kind + span.source
            let rendered = storage.syntaxImages[key]
            let diagnostic = storage.syntaxDiagnostics[key]
            guard let frame = (view as? MarkdownInternalTextView)?.syntaxPreviewRect(for: span) else { continue }
            let button: UIButton
            if let existing = views[span.range.location] { button = existing }
            else {
                button = UIButton(type: .custom)
                button.accessibilityIdentifier = "markdown.media.overlay.syntax.\(span.range.location)"
                view.addSubview(button); views[span.range.location] = button
            }
            button.removeAction(identifiedBy: UIAction.Identifier("syntax.open"), for: .touchUpInside)
            button.setImage(storage.syntaxPreviewHeights[span.range.location] == nil ? nil : rendered?.image, for: .normal)
            button.imageView?.contentMode = .scaleAspectFit
            button.contentHorizontalAlignment = .center
            button.contentVerticalAlignment = .center
            button.setTitle(rendered == nil ? (diagnostic.map { "⚠ " + $0 } ?? "Rendering…") : nil, for: .normal)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
            button.setTitleColor(diagnostic == nil ? .secondaryLabel : .systemRed, for: .normal)
            button.accessibilityLabel = diagnostic ?? (span.kind == "diagram" ? "Diagram: \(span.source)" : "Equation: \(span.source)")
            button.accessibilityHint = "While editing, reveals and selects the source content. Otherwise opens a preview."
            button.addAction(UIAction(identifier: UIAction.Identifier("syntax.open")) { [weak view] _ in
                guard let view else { return }
                if view.isMarkdownEditingActive || rendered == nil {
                    view.becomeFirstResponder()
                    view.selectedRange = span.contentRange
                    view.delegate?.textViewDidChangeSelection?(view)
                } else if let rendered {
                    var responder: UIResponder? = view
                    while let current = responder {
                        if let controller = current as? UIViewController {
                            controller.present(UIHostingController(rootView: RenderedSyntaxViewer(rendered: rendered)), animated: true)
                            break
                        }
                        responder = current.next
                    }
                }
            }, for: .touchUpInside)
            button.frame = frame
        }
    }
}
