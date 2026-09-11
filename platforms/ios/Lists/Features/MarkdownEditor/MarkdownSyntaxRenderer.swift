import UIKit
import WebKit

struct MarkdownRenderedSource: Equatable {
    let range: NSRange
    let source: String
    let kind: String
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
            result.append(Self(range: range, source: body, kind: "diagram"))
        }
        let inlineCode = (try? NSRegularExpression(pattern: #"(`+)[^\n]*?\1"#))?.matches(in: source, range: NSRange(location: 0, length: ns.length)).map(\.range) ?? []
        for (pattern, kind) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                if result.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) { continue }
                if kind != "diagram", (code + inlineCode).contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
                result.append(Self(range: match.range, source: ns.substring(with: match.range(at: 1)), kind: kind))
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

@MainActor final class MarkdownSyntaxRenderer: NSObject, WKNavigationDelegate {
    static let shared = MarkdownSyntaxRenderer()
    private let webView: WKWebView
    private var loaded = false
    private var loadError: Error?
    private var queue: Task<Void, Never>?
    private let cache = NSCache<NSString, MarkdownRenderedImage>()
    private var failures: Set<String> = []
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
    func result(_ span: MarkdownRenderedSource, width: CGFloat, fontSize: CGFloat, dark: Bool) -> MarkdownRenderedImage? {
        let key = key(span, width: width, fontSize: fontSize, dark: dark)
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard !pending.contains(key), !failures.contains(key), width > 1 else { return nil }
        guard span.source.utf16.count <= 30000 else { failures.insert(key); return nil }
        pending.insert(key)
        let previous = queue
        queue = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            defer { self.pending.remove(key); NotificationCenter.default.post(name: Self.didRender, object: nil) }
            do {
                for _ in 0..<100 where !self.loaded && self.loadError == nil { try await Task.sleep(for: .milliseconds(100)) }
                guard self.loaded else { throw self.loadError ?? CocoaError(.fileReadUnknown) }
                self.webView.frame.size = CGSize(width: width, height: 1600)
                let value = try await self.webView.callAsyncJavaScript("return await window.renderDocumentSyntax(source,kind,dark,size,width)", arguments: ["source": span.source, "kind": span.kind, "dark": dark, "size": fontSize, "width": width], in: nil, contentWorld: .page)
                guard let dimensions = value as? [String: Double], let w = dimensions["width"], let h = dimensions["height"], w > 0, h > 0 else { throw CocoaError(.coderInvalidValue) }
                let configuration = WKSnapshotConfiguration()
                configuration.rect = CGRect(x: 0, y: 0, width: w, height: h)
                let image = try await self.webView.takeSnapshot(configuration: configuration)
                let rendered = MarkdownRenderedImage(image: image, kind: span.kind, source: span.source)
                self.cache.setObject(rendered, forKey: key as NSString, cost: Int(w * h * image.scale * image.scale * 4))
            } catch { self.failures.insert(key) }
        }
        return nil
    }
    func failed(_ span: MarkdownRenderedSource, width: CGFloat, fontSize: CGFloat, dark: Bool) -> Bool { failures.contains(key(span, width: width, fontSize: fontSize, dark: dark)) }
}

import SwiftUI

struct RenderedSyntaxPreview: View {
    let source: String
    let kind: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var rendered: MarkdownRenderedImage?
    @State private var failed = false
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
                if failed { Label("Couldn’t render. Check the source syntax.", systemImage: "exclamationmark.triangle").font(.caption) }
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
        rendered = renderer.result(span, width: 340, fontSize: UIFont.preferredFont(forTextStyle: .body).pointSize, dark: colorScheme == .dark)
        failed = renderer.failed(span, width: 340, fontSize: UIFont.preferredFont(forTextStyle: .body).pointSize, dark: colorScheme == .dark)
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
    private var failureViews: [Int: UIButton] = [:]
    private let attachmentSelection: MarkdownAttachmentSelection
    private var selectionControls: [Int: UIStackView] = [:]
    init(textView: UITextView, attachmentSelection: MarkdownAttachmentSelection) {
        self.textView = textView
        self.attachmentSelection = attachmentSelection
    }
    func refresh() {
        guard let view = textView, let storage = view.textStorage as? MarkdownStyler else { return }
        let failures = storage.mode == .live ? MarkdownRenderedSource.spans(in: storage.string).filter {
            $0.kind != "inline" && storage.syntaxFailures.contains($0.kind + $0.source)
                && (storage.cursorRange.location == NSNotFound || storage.cursorRange.location < $0.range.location || storage.cursorRange.location > NSMaxRange($0.range))
        } : []
        for button in failureViews.values { button.removeFromSuperview() }
        failureViews.removeAll()
        for span in failures {
            let line = view.layoutManager.lineFragmentRect(forGlyphAt: view.layoutManager.glyphIndexForCharacter(at: span.range.location), effectiveRange: nil)
            let button = UIButton(type: .system)
            button.setTitle("Couldn’t render · Edit source", for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
            button.tintColor = .systemRed
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = "markdown.media.overlay.error.\(span.range.location)"
            button.addAction(UIAction { [weak view] _ in view?.becomeFirstResponder(); view?.selectedRange = span.range }, for: .touchUpInside)
            button.frame = CGRect(x: view.textContainerInset.left, y: view.textContainerInset.top + line.minY - 24, width: view.bounds.width - view.textContainerInset.left - view.textContainerInset.right, height: 24)
            view.addSubview(button); failureViews[span.range.location] = button
        }
        let spans = storage.mode == .live ? MarkdownRenderedSource.spans(in: storage.string).filter { $0.kind != "inline" && storage.renderedImage(at: $0.range.location) != nil } : []
        let ids = Set(spans.map { $0.range.location })
        for id in Array(views.keys) where !ids.contains(id) { views.removeValue(forKey: id)?.removeFromSuperview(); selectionControls.removeValue(forKey: id)?.removeFromSuperview() }
        for span in spans {
            guard let rendered = storage.renderedImage(at: span.range.location) else { continue }
            let glyph = view.layoutManager.glyphIndexForCharacter(at: span.range.location)
            let line = view.layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let location = view.layoutManager.location(forGlyphAt: glyph)
            if views[span.range.location]?.accessibilityLabel != (span.kind == "diagram" ? "Diagram: \(span.source)" : "Equation: \(span.source)") {
                views.removeValue(forKey: span.range.location)?.removeFromSuperview()
                let button = UIButton(type: .custom)
                button.accessibilityIdentifier = "markdown.media.overlay.syntax.\(span.range.location)"
                button.accessibilityLabel = span.kind == "diagram" ? "Diagram: \(span.source)" : "Equation: \(span.source)"
                button.accessibilityHint = "While editing, selects the block and shows Open and Edit Markdown. Otherwise opens a preview."
                let open: () -> Void = { [weak self] in
                    guard let self else { return }
                    self.attachmentSelection.clear()
                    var responder: UIResponder? = self.textView
                    while let current = responder {
                        if let controller = current as? UIViewController {
                            controller.present(UIHostingController(rootView: RenderedSyntaxViewer(rendered: rendered)), animated: true)
                            break
                        }
                        responder = current.next
                    }
                }
                button.addAction(UIAction { [weak self] _ in
                    if self?.attachmentSelection.select("syntax.\(span.range.location)") != true { open() }
                }, for: .touchUpInside)
                let edit: () -> Void = { [weak self, weak view] in
                    self?.attachmentSelection.clear()
                    view?.becomeFirstResponder(); view?.selectedRange = span.range
                }
                let actions = UIStackView()
                actions.axis = .horizontal
                actions.spacing = 8
                for (title, id, action) in [("Open", "open", open), ("Edit Markdown", "source", edit)] {
                    let control = UIButton(type: .system)
                    var configuration = UIButton.Configuration.tinted()
                    configuration.title = title
                    configuration.cornerStyle = .capsule
                    configuration.buttonSize = .small
                    control.configuration = configuration
                    control.accessibilityIdentifier = "markdown.syntax.selected.\(id).\(span.range.location)"
                    control.addAction(UIAction { _ in action() }, for: .touchUpInside)
                    control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                    actions.addArrangedSubview(control)
                }
                view.addSubview(actions)
                selectionControls[span.range.location]?.removeFromSuperview()
                selectionControls[span.range.location] = actions
                button.menu = UIMenu(children: [UIAction(title: "Edit Markdown", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")) { _ in
                    edit()
                }])
                view.addSubview(button); views[span.range.location] = button
            }
            views[span.range.location]?.frame = CGRect(x: view.textContainerInset.left + line.minX + location.x, y: view.textContainerInset.top + line.minY, width: max(1, view.bounds.width - view.textContainerInset.left - view.textContainerInset.right - line.minX - location.x), height: max(line.height, rendered.image.size.height))
            let selected = attachmentSelection.selectedID == "syntax.\(span.range.location)"
            if let button = views[span.range.location] {
                button.layer.borderWidth = selected ? 1.5 : 0
                button.layer.borderColor = view.tintColor.withAlphaComponent(0.65).cgColor
                button.layer.cornerRadius = 8
                if let controls = selectionControls[span.range.location] {
                    controls.isHidden = !selected
                    let size = controls.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
                    controls.frame = CGRect(x: max(button.frame.minX, button.frame.maxX - size.width - 4),
                        y: button.frame.minY + 4, width: size.width, height: max(44, size.height))
                    view.bringSubviewToFront(controls)
                }
            }
        }
    }
}
