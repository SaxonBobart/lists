import Foundation
import JavaScriptCore
import UIKit

struct MarkdownCodeToken: Codable, Equatable, Sendable {
    let location: Int
    let length: Int
    let scope: String

    var role: MarkdownCodeTokenRole {
        if scope.contains("comment") { return .comment }
        if scope.contains("string") || scope.contains("regexp") { return .string }
        if scope.contains("number") || scope.contains("literal") { return .number }
        if scope.contains("keyword") || scope.contains("built_in") { return .keyword }
        if scope.contains("title") || scope.contains("type") { return .type }
        if scope.contains("attr") || scope.contains("property") { return .property }
        return .plain
    }
}

/// Semantic roles form the theme boundary; Highlight.js never supplies colors.
enum MarkdownCodeTokenRole: String, Sendable {
    case plain, comment, string, number, keyword, type, property
    var color: UIColor {
        switch self {
        case .plain: .label
        case .comment: .secondaryLabel
        case .string: .systemOrange
        case .number: .systemPurple
        case .keyword: .systemBlue
        case .type: .systemTeal
        case .property: .systemIndigo
        }
    }
}

struct MarkdownCodeLanguage: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let aliases: [String]

    static let all: [Self] = {
        guard let url = Bundle.main.url(forResource: "languages", withExtension: "json", subdirectory: "EditorRenderers/highlight"),
              let data = try? Data(contentsOf: url), let languages = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return (languages + [Self(id: "mermaid", name: "Mermaid", aliases: [])]).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    static func matching(_ query: String) -> [Self] {
        guard !query.isEmpty else { return all }
        return all.filter { [$0.id, $0.name] + $0.aliases ~= query }
    }
}

private func ~= (names: [String], query: String) -> Bool {
    names.contains { $0.range(of: query, options: [.caseInsensitive, .anchored]) != nil }
}

struct MarkdownCodeCompletion: Equatable {
    let range: NSRange
    let query: String

    static func at(_ selection: NSRange, in source: String) -> Self? {
        guard selection.length == 0, selection.location <= source.utf16.count else { return nil }
        let ns = source as NSString
        for block in MarkdownFenceSyntax.blocks(in: source) {
            let line = ns.lineRange(for: NSRange(location: block.fullRange.location, length: 0))
            let content = MarkdownSyntax.lineContent(in: ns, range: line)
            guard let marker = MarkdownFenceSyntax.marker(in: content) else { continue }
            let leading = content.prefix { $0 == " " }.utf16.count + marker.count
            let suffix = (content as NSString).substring(from: leading)
            let space = suffix.prefix { $0 == " " || $0 == "\t" }.utf16.count
            let token = suffix.dropFirst(space).prefix { !$0.isWhitespace }
            let start = line.location + leading + space
            let end = start + token.utf16.count
            guard selection.location >= start, selection.location <= end else { continue }
            return Self(range: NSRange(location: start, length: token.utf16.count), query: ns.substring(with: NSRange(location: start, length: selection.location - start)))
        }
        return nil
    }
}

actor MarkdownCodeHighlighter {
    static let shared = MarkdownCodeHighlighter()
    private var context: JSContext?
    private var cache: [String: [MarkdownCodeToken]] = [:]

    static func key(language: String, source: String) -> String { language.lowercased() + "\u{0}" + source }

    func tokens(source: String, language: String) -> [MarkdownCodeToken] {
        let key = Self.key(language: language, source: source)
        if let cached = cache[key] { return cached }
        guard source.utf16.count <= 100_000 else { return [] }
        if context == nil {
            guard let url = Bundle.main.url(forResource: "highlight.min", withExtension: "js", subdirectory: "EditorRenderers/highlight"),
                  let script = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            context = JSContext()
            context?.evaluateScript(script)
        }
        guard let values = context?.objectForKeyedSubscript("ListsHighlight")?.invokeMethod("tokens", withArguments: [source, language.lowercased()])?.toArray(),
              let data = try? JSONSerialization.data(withJSONObject: values),
              let tokens = try? JSONDecoder().decode([MarkdownCodeToken].self, from: data) else { return [] }
        if cache.count >= 128 { cache.removeAll(keepingCapacity: true) }
        cache[key] = tokens
        return tokens
    }
}

@MainActor
final class MarkdownCodeCompletionController {
    private weak var textView: MarkdownInternalTextView?
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var completion: MarkdownCodeCompletion?
    private var candidates: [MarkdownCodeLanguage] = []
    private var dismissedCompletion: MarkdownCodeCompletion?
    private(set) var selectedIndex: Int?
    var insert: ((NSRange, String) -> Void)?
    var isVisible: Bool { !scrollView.isHidden && scrollView.superview != nil }

    init(textView: MarkdownInternalTextView) {
        self.textView = textView
        scrollView.backgroundColor = .secondarySystemBackground
        scrollView.layer.cornerRadius = 12
        scrollView.layer.borderColor = UIColor.separator.cgColor
        scrollView.layer.borderWidth = 0.5
        scrollView.accessibilityIdentifier = "markdown.code.languages"
        stack.axis = .vertical
        scrollView.addSubview(stack)
        scrollView.isHidden = true
        textView.addSubview(scrollView)
    }

    func refresh() {
        guard let textView, textView.isFirstResponder,
              let storage = textView.textStorage as? MarkdownStyler, storage.mode == .live,
              let next = MarkdownCodeCompletion.at(textView.selectedRange, in: storage.string),
              next != dismissedCompletion else { scrollView.isHidden = true; completion = nil; return }
        if completion != next {
            completion = next; selectedIndex = nil
            candidates = MarkdownCodeLanguage.matching(next.query)
            for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
            for (index, language) in candidates.enumerated() {
                let button = UIButton(type: .system)
                button.setTitle(language.name + "  ·  " + language.id, for: .normal)
                button.titleLabel?.font = .preferredFont(forTextStyle: .callout)
                button.contentHorizontalAlignment = .leading
                button.configuration = .plain()
                button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                button.accessibilityIdentifier = "markdown.code.language.\(language.id)"
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                button.addAction(UIAction { [weak self] _ in self?.choose(index) }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
            scrollView.contentOffset = .zero
        }
        scrollView.isHidden = candidates.isEmpty
        guard !candidates.isEmpty, let position = textView.position(from: textView.beginningOfDocument, offset: textView.selectedRange.location) else { return }
        let caret = textView.caretRect(for: position)
        let width = min(300, textView.bounds.width - 8)
        let rowHeight = max(44, UIFont.preferredFont(forTextStyle: .callout).lineHeight + 16)
        let height = min(CGFloat(candidates.count), 5) * rowHeight
        // A fence near the top of the note has no room above it. Keep the
        // typing line visible and place suggestions underneath in that case.
        let above = caret.minY - height - 8
        let y = above >= textView.bounds.minY ? above : caret.maxY + 8
        scrollView.frame = CGRect(x: max(0, min(caret.minX, textView.bounds.width - width)), y: y, width: width, height: height)
        stack.frame = CGRect(x: 0, y: 0, width: width, height: CGFloat(candidates.count) * rowHeight)
        scrollView.contentSize = stack.frame.size
        textView.bringSubviewToFront(scrollView)
    }
    func move(_ delta: Int) {
        guard !candidates.isEmpty else { return }
        selectedIndex = min(candidates.count - 1, max(0, (selectedIndex ?? (delta > 0 ? -1 : candidates.count)) + delta))
        for (index, button) in stack.arrangedSubviews.enumerated() {
            button.backgroundColor = index == selectedIndex ? .tertiarySystemFill : .clear
        }
        if let selectedIndex { scrollView.scrollRectToVisible(stack.arrangedSubviews[selectedIndex].frame, animated: false) }
    }
    func accept() { if let selectedIndex { choose(selectedIndex) } }
    func dismiss() { dismissedCompletion = completion; scrollView.isHidden = true }
    private func choose(_ index: Int) {
        guard candidates.indices.contains(index), let completion else { return }
        let language = candidates[index]
        scrollView.isHidden = true
        dismissedCompletion = MarkdownCodeCompletion(range: NSRange(location: completion.range.location, length: language.id.utf16.count), query: language.id)
        insert?(completion.range, language.id)
    }
}
