import SwiftUI
import UIKit

enum MarkdownProseAssistance {
    static func allowsAssistance(source: String, selection: NSRange, raw: Bool) -> Bool {
        guard !raw else { return false }
        let prefix = (source as NSString).substring(to: min(selection.location, (source as NSString).length))
        let fences = MarkdownFenceSyntax.blocks(in: prefix)
        guard !fences.contains(where: { !$0.isClosed }) else { return false }
        let ns = prefix as NSString
        var math = false
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, _, range, _ in
            guard !fences.contains(where: { NSLocationInRange(range.location, $0.fullRange) }) else { return }
            if line?.trimmingCharacters(in: .whitespaces) == "$$" { math.toggle() }
        }
        guard !math else { return false }
        let line = prefix.components(separatedBy: "\n").last ?? ""
        if line.filter({ $0 == "`" }).count % 2 != 0 || line.filter({ $0 == "$" }).count % 2 != 0 { return false }
        if let start = line.range(of: "](", options: .backwards), !line[start.upperBound...].contains(")") { return false }
        let word = line.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        return !word.contains("://") && !word.hasPrefix("Attachments/")
    }
    @MainActor static func update(_ view: UITextView) {
        guard view.markedTextRange == nil else { return }
        let enabled = allowsAssistance(source: view.text ?? "", selection: view.selectedRange, raw: (view.textStorage as? MarkdownStyler)?.mode == .raw)
        view.autocorrectionType = enabled ? .yes : .no
        view.spellCheckingType = enabled ? .yes : .no
    }
}

enum DocumentReplacement {
    static func ranges(of query: String, in source: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let ns = source as NSString
        var result: [NSRange] = []
        var offset = 0
        while offset < ns.length {
            let match = ns.range(of: query, options: [.caseInsensitive], range: NSRange(location: offset, length: ns.length - offset))
            guard match.location != NSNotFound else { break }
            result.append(match); offset = NSMaxRange(match)
        }
        return result
    }
    static func replaceAll(_ query: String, with replacement: String, in source: String) -> String {
        var result = source
        for range in ranges(of: query, in: source).reversed() { result = (result as NSString).replacingCharacters(in: range, with: replacement) }
        return result
    }
}

struct DocumentFindReplaceView: View {
    let source: String
    let onReplace: (String) -> Void
    let onFind: (NSRange) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var replacement = ""
    private var matches: [NSRange] { DocumentReplacement.ranges(of: query, in: source) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Find in document", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("document.find.query")
                    TextField("Replace with", text: $replacement).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("document.find.replacement")
                    Text(matches.count == 1 ? "1 match" : "\(matches.count) matches").foregroundStyle(.secondary)
                    Button("Replace All") { onReplace(DocumentReplacement.replaceAll(query, with: replacement, in: source)) }
                        .disabled(matches.isEmpty).accessibilityIdentifier("document.find.replaceall")
                } footer: { Text("Searches the Markdown body, including source syntax. Changes can be undone in the editor.") }
                Section("Matches") {
                    ForEach(matches, id: \.location) { range in
                        HStack {
                            Button {
                                onFind(range)
                            } label: {
                                let ns = source as NSString
                                let start = max(0, range.location - 24)
                                Text(ns.substring(with: NSRange(location: start, length: min(ns.length - start, range.length + 48)))).lineLimit(2)
                            }.accessibilityIdentifier("document.find.match.\(range.location)")
                            Spacer()
                            Button("Replace") { onReplace((source as NSString).replacingCharacters(in: range, with: replacement)) }
                                .buttonStyle(.borderless).accessibilityIdentifier("document.find.replace.\(range.location)")
                        }
                    }
                }
            }
            .navigationTitle("Find and Replace").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Done", systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly).accessibilityIdentifier("document.find.done")
            } }
        }
    }
}

struct EditorHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let sections: [(String, String)] = [
        ("Writing", "Tap the body to write. Aa opens formatting. Swipe the keyboard toolbar for more actions. Live mode renders Markdown; Raw Markdown shows its exact source. Undo, Redo, and Find and Replace are in More."),
        ("Formatting", "# Heading\n**bold** · *italic* · ~~strikethrough~~\n`inline code` · ==highlight==\n- Bullet\n1. Numbered list\n- [ ] Checklist\n> Quote\n\nUse fenced blocks for code. Callouts begin with > [!NOTE], TIP, IMPORTANT, WARNING, or CAUTION."),
        ("Tables", "Insert a table from the toolbar. Tap a cell to write. Return adds a new line within the cell; Tab moves between cells. Row and column handles select, move, insert, or delete; drag the grips to select a range. Pasting rectangular spreadsheet data creates a table."),
        ("Links and navigation", "The link button chooses a document or heading. Paste a URL over selected words to make a web link. Document Navigator contains headings, links, backlinks, and Find. Web links never fetch a preview automatically."),
        ("Attachments", "The paperclip adds photos, videos, scans, files, or an audio recording. Files appear as compact links: [title](path). Photos use image Markdown: ![description](path), which displays the image in your note. Tap either to open the full viewer. Touch and hold an image to switch between Show Image and Show as Link; this only adds or removes the ! in its Markdown. The menu also offers sharing, descriptions, replacement, and removal. Removing a reference does not immediately delete the file. Keep the whole exported library together so links continue to work."),
        ("Equations and diagrams", "Use $x^2$ for inline math, $$ on separate lines for a display equation, and a fenced mermaid block for diagrams. Edit source to change the result. Rendering works offline."),
        ("Keyboard", "⌘Z Undo · ⇧⌘Z Redo\nTab / Shift-Tab navigate table cells or indent lists. Use keyboard shortcut discovery for link and table commands.")
    ]
    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { entry in Section(entry.0) { Text(entry.1) } }
            }
            .navigationTitle("Editor Help").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Done", systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly).accessibilityIdentifier("document.help.done")
            } }
        }
    }
}
