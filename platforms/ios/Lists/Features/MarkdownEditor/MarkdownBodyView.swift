import MarkdownUI
import SwiftUI
import ImageIO

/// Read-only GFM renderer for full note bodies. Plain CommonMark/GFM bodies
/// stay on MarkdownUI; bodies with Lists' semantic highlight extension use a
/// lightweight path so `==text==` can render with the active theme token.
struct MarkdownBodyView: View {
    struct LinkPresentation {
        let title: String
        let subtitle: String
        let systemImage: String
    }

    let source: String
    let linkPresentation: ((URL) -> LinkPresentation?)?

    init(_ source: String, linkPresentation: ((URL) -> LinkPresentation?)? = nil) {
        self.source = source
        self.linkPresentation = linkPresentation
    }

    var body: some View {
        if Self.usesSemanticHighlightRenderer(source) {
            SemanticMarkdownBody(source: source, linkPresentation: linkPresentation)
        } else {
            Markdown(source)
                .markdownTheme(.gitHub)
                // Privacy: never fetch remote images from note bodies. The `.asset`
                // providers resolve bundle assets only (no URLSession), so a remote
                // `![](http...)` renders as nothing instead of pinging a third-party
                // server and leaking the user's IP.
                .markdownImageProvider(.asset)
                .markdownInlineImageProvider(.asset)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func usesSemanticHighlightRenderer(_ source: String) -> Bool {
        source.contains("==")
            || source.contains("<mark data-color=")
            || source.contains("$")
            || source.contains("```mermaid")
            || source.contains("(lists://item/")
            || source.contains("> [!")
            || source.range(of: #"(?m)^\s*>"#, options: .regularExpression) != nil
            || source.range(of: #"(?m)^\[[^\]\n]+\]\([^\)\n]+\)$"#, options: .regularExpression) != nil
            || MarkdownSyntax.tableBlockRanges(in: source).isEmpty == false
    }

    static func rendersStandaloneLinkAsCard(destination: String) -> Bool {
        MarkdownAttachmentIndex.isSafeRelativePath(destination)
    }
}

private struct SemanticMarkdownBody: View {
    private let blocks: [SemanticMarkdownBlock]
    private let linkPresentation: ((URL) -> MarkdownBodyView.LinkPresentation?)?
    @Environment(\.openURL) private var openURL
    @State private var previewURL: URL?

    init(source: String, linkPresentation: ((URL) -> MarkdownBodyView.LinkPresentation?)?) {
        self.blocks = SemanticMarkdownBlockParser.blocks(from: source)
        self.linkPresentation = linkPresentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .quickLookPreview($previewURL)
    }

    private func blockView(_ block: SemanticMarkdownBlock) -> AnyView {
        switch block.kind {
        case .heading(let level, let text):
            AnyView(inlineText(text, font: headingFont(level))
                .padding(.top, level == 1 ? 4 : 2)
            )
        case .paragraph(let text):
            AnyView(inlineText(text))
        case .bullet(let indent, let text):
            AnyView(listRow(marker: "•", indent: indent, text: text))
        case .ordered(let indent, let number, let text):
            AnyView(listRow(marker: "\(number).", indent: indent, text: text))
        case .task(let indent, let checked, let text):
            AnyView(taskRow(checked: checked, indent: indent, text: text))
        case .quote(let blocks):
            AnyView(quoteBlock(blocks))
        case .callout(let callout):
            AnyView(calloutBlock(callout))
        case .linkCard(let label, let url):
            AnyView(linkCard(label: label, url: url))
        case .image(let alt, let path):
            AnyView(LocalMarkdownImage(alt: alt, relativePath: path))
        case .codeBlock(let text):
            AnyView(Text(text.isEmpty ? " " : text)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemFill))
                }
            )
        case .mathBlock(let text):
            AnyView(labeledCodeBlock(label: "Math", systemImage: "function", text: text))
        case .mermaid(let text):
            AnyView(labeledCodeBlock(label: "Mermaid", systemImage: "chart.bar.doc.horizontal", text: text))
        case .table(let headers, let alignments, let rows):
            AnyView(tableView(headers: headers, alignments: alignments, rows: rows))
        case .divider:
            AnyView(Divider()
                .padding(.vertical, 4)
            )
        }
    }

    private func inlineText(_ source: String, font: Font = .body) -> Text {
        Text(SemanticMarkdownInlineRenderer.attributedString(for: source, baseFont: font))
    }

    private func listRow(marker: String, indent: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: marker == "•" ? 16 : 28, alignment: .trailing)
            inlineText(text)
        }
        .padding(.leading, CGFloat(indent) * 18)
    }

    private func taskRow(checked: Bool, indent: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.body)
                .foregroundStyle(checked ? ListsTokens.accent : Color(.secondaryLabel))
                .frame(width: 20, alignment: .center)
            inlineText(text)
        }
        .padding(.leading, CGFloat(indent) * 18)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .largeTitle.bold()
        case 2: return .title.bold()
        case 3: return .title2.bold()
        case 4: return .title3.bold()
        case 5: return .subheadline.bold()
        case 6: return .footnote.bold()
        default: return .headline
        }
    }

    private func quoteBlock(_ blocks: [SemanticMarkdownBlock]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .markdownQuoteCard(tint: Color(.secondaryLabel))
    }

    private func calloutBlock(_ callout: MarkdownCallout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: callout.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(callout.kind.tint)
                    .accessibilityHidden(true)
                Text(callout.title ?? callout.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(callout.kind.tint)
            }

            if callout.body.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(callout.body) { block in
                        blockView(block)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .markdownQuoteCard(tint: callout.kind.tint)
    }

    private func linkCard(label: String, url: URL) -> some View {
        let presentation = linkPresentation?(url) ?? fallbackPresentation(label: label, url: url)
        return Button {
            if MarkdownAttachmentIndex.isSafeRelativePath(url.relativeString) {
                previewURL = StorageRoot.defaultListsDirectory().appendingPathComponent(url.relativeString)
            } else {
                openURL(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: presentation.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ListsTokens.accent)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ListsTokens.Foreground.primary)
                        .lineLimit(1)
                    Text(presentation.subtitle)
                        .font(ListsTypography.caption1)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(.separator).opacity(0.65), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(presentation.subtitle)
        .accessibilityHint("Opens the link")
    }

    private func fallbackPresentation(label: String, url: URL) -> MarkdownBodyView.LinkPresentation {
        if DocumentMarkdownIndex.itemId(from: url) != nil {
            return MarkdownBodyView.LinkPresentation(
                title: label.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Linked document",
                subtitle: "Document",
                systemImage: "doc.text"
            )
        }
        if MarkdownAttachmentIndex.isSafeRelativePath(url.relativeString) {
            return MarkdownBodyView.LinkPresentation(
                title: label.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url.lastPathComponent,
                subtitle: url.lastPathComponent,
                systemImage: "paperclip"
            )
        }
        return MarkdownBodyView.LinkPresentation(
            title: label.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url.host ?? url.absoluteString,
            subtitle: url.host ?? url.absoluteString,
            systemImage: "link"
        )
    }

    private func labeledCodeBlock(label: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? " " : text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemFill))
        }
    }

    private func tableView(headers: [String],
                           alignments: [MarkdownTableAlignment],
                           rows: [[String]]) -> some View {
        let columnCount = max(1, headers.count, alignments.count, rows.map(\.count).max() ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            tableRow(cells: normalizedTableRow(headers, count: columnCount),
                     alignments: alignments,
                     isHeader: true)
            ForEach(rows.enumerated().map(SemanticMarkdownTableRow.init), id: \.id) { row in
                tableRow(cells: normalizedTableRow(row.cells, count: columnCount),
                         alignments: alignments,
                         isHeader: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MarkdownTableVisualMetrics.cornerRadius,
                                    style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MarkdownTableVisualMetrics.cornerRadius,
                             style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        }
    }

    private func normalizedTableRow(_ cells: [String], count: Int) -> [String] {
        Array(cells.prefix(count)) + Array(repeating: "", count: max(0, count - cells.count))
    }

    private func tableRow(cells: [String],
                          alignments: [MarkdownTableAlignment],
                          isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(cells.enumerated().map(SemanticMarkdownTableCell.init), id: \.id) { cell in
                let alignment = alignments.indices.contains(cell.id) ? alignments[cell.id] : .none
                inlineText(cell.text.isEmpty ? " " : cell.text)
                    .font(isHeader ? .body.weight(.semibold) : .body)
                    .padding(.horizontal, MarkdownTableVisualMetrics.horizontalCellPadding)
                    .padding(.vertical, MarkdownTableVisualMetrics.verticalCellPadding)
                    .frame(maxWidth: .infinity, alignment: frameAlignment(for: alignment))
            }
        }
        .background(isHeader ? Color(.secondarySystemFill) : Color.clear)
        .overlay {
            GeometryReader { proxy in
                ForEach(1..<max(1, cells.count), id: \.self) { column in
                    let x = proxy.size.width * CGFloat(column) / CGFloat(max(1, cells.count))
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 0.5)
                        .offset(x: x)
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
    }

    private func frameAlignment(for alignment: MarkdownTableAlignment) -> Alignment {
        switch alignment {
        case .right:
            return .trailing
        case .center:
            return .center
        default:
            return .leading
        }
    }
}

private extension View {
    func markdownQuoteCard(tint: Color) -> some View {
        modifier(MarkdownQuoteCardModifier(tint: tint))
    }
}

private struct MarkdownQuoteCardModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: MarkdownQuoteCardMetrics.cornerRadius,
            style: .continuous
        )
        content
            .padding(.leading, MarkdownQuoteCardMetrics.contentLeadingPadding)
            .padding(.trailing, MarkdownQuoteCardMetrics.contentTrailingPadding)
            .padding(.vertical, MarkdownQuoteCardMetrics.contentVerticalPadding)
            .background {
                ZStack(alignment: .leading) {
                    shape.fill(tint.opacity(0.10))
                    Rectangle()
                        .fill(tint)
                        .frame(width: MarkdownQuoteCardMetrics.railWidth)
                        .frame(maxHeight: .infinity)
                }
                .clipShape(shape)
            }
            .overlay {
                shape.stroke(tint.opacity(0.24), lineWidth: 0.5)
            }
    }
}

private struct SemanticMarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(indent: Int, text: String)
        case ordered(indent: Int, number: Int, text: String)
        case task(indent: Int, checked: Bool, text: String)
        case quote([SemanticMarkdownBlock])
        case callout(MarkdownCallout)
        case linkCard(label: String, url: URL)
        case image(alt: String, relativePath: String)
        case codeBlock(String)
        case mathBlock(String)
        case mermaid(String)
        case table(headers: [String], alignments: [MarkdownTableAlignment], rows: [[String]])
        case divider
    }

    let id: Int
    let kind: Kind
}

private struct SemanticMarkdownTableRow: Identifiable {
    let id: Int
    let cells: [String]

    init(offset: Int, element: [String]) {
        id = offset
        cells = element
    }
}

private struct SemanticMarkdownTableCell: Identifiable {
    let id: Int
    let text: String

    init(offset: Int, element: String) {
        id = offset
        text = element.trimmingCharacters(in: .whitespaces)
    }
}

private struct LocalMarkdownImage: View {
    let alt: String
    let relativePath: String
    @State private var image: UIImage?
    @State private var previewURL: URL?

    private var fileURL: URL {
        StorageRoot.defaultListsDirectory().appendingPathComponent(relativePath)
    }

    var body: some View {
        Button {
            previewURL = fileURL
        } label: {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.55), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(alt.nilIfEmpty ?? "Attached image")
        .accessibilityHint("Opens a full-size preview")
        .accessibilityIdentifier("markdown.attachment.image")
        .task(id: relativePath) {
            image = await Self.thumbnail(at: fileURL, maximumPixelSize: 1600)
        }
        .quickLookPreview($previewURL)
    }

    private static func thumbnail(at url: URL, maximumPixelSize: Int) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

private struct MarkdownCallout {
    let kind: MarkdownCalloutKind
    let title: String?
    let body: [SemanticMarkdownBlock]
}

private enum MarkdownCalloutKind: String, Hashable {
    case note
    case tip
    case important
    case warning
    case caution

    init?(_ raw: String) {
        self.init(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    var title: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .caution: return "Caution"
        }
    }

    var systemImage: String {
        switch self {
        case .note: return "info.circle"
        case .tip: return "lightbulb"
        case .important: return "star.circle"
        case .warning: return "exclamationmark.triangle"
        case .caution: return "hand.raised"
        }
    }

    var tint: Color {
        switch self {
        case .note: return ListsTokens.accent
        case .tip: return .green
        case .important: return .purple
        case .warning: return .orange
        case .caution: return .red
        }
    }
}

private enum SemanticMarkdownBlockParser {
    private static let headingRegex = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.+)$"#)
    private static let bulletRegex = try! NSRegularExpression(pattern: #"^(\s*)[-*+]\s+(.+)$"#)
    private static let taskRegex = try! NSRegularExpression(pattern: #"^(\s*)[-*+]\s+\[([ xX])\]\s+(.+)$"#)
    private static let orderedRegex = try! NSRegularExpression(pattern: #"^(\s*)(\d+)\.\s+(.+)$"#)
    private static let calloutMarkerRegex = try! NSRegularExpression(pattern: #"^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][+-]?(?:\s+(.*))?$"#, options: [.caseInsensitive])
    private static let standaloneLinkRegex = try! NSRegularExpression(pattern: #"^\[([^\]\n]+)\]\(([^)\n]+)\)$"#)
    private static let localImageRegex = try! NSRegularExpression(pattern: #"^!\[([^\]\n]*)\]\((Attachments/[^)\n]+)\)$"#)

    static func blocks(from source: String) -> [SemanticMarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [SemanticMarkdownBlock] = []
        var paragraphLines: [String] = []
        var lineIndex = 0

        func append(_ kind: SemanticMarkdownBlock.Kind) {
            blocks.append(SemanticMarkdownBlock(id: blocks.count, kind: kind))
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll()
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                lineIndex += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                lineIndex += 1
                var codeLines: [String] = []
                while lineIndex < lines.count {
                    let codeLine = lines[lineIndex]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        lineIndex += 1
                        break
                    }
                    codeLines.append(codeLine)
                    lineIndex += 1
                }
                if language == "mermaid" {
                    append(.mermaid(codeLines.joined(separator: "\n")))
                } else {
                    append(.codeBlock(codeLines.joined(separator: "\n")))
                }
                continue
            }

            if trimmed == "$$" {
                flushParagraph()
                lineIndex += 1
                var mathLines: [String] = []
                while lineIndex < lines.count {
                    let mathLine = lines[lineIndex]
                    if mathLine.trimmingCharacters(in: .whitespaces) == "$$" {
                        lineIndex += 1
                        break
                    }
                    mathLines.append(mathLine)
                    lineIndex += 1
                }
                append(.mathBlock(mathLines.joined(separator: "\n")))
                continue
            }

            if lineIndex + 1 < lines.count,
               MarkdownSyntax.isTableRow(line),
               MarkdownSyntax.isTableDivider(lines[lineIndex + 1]) {
                flushParagraph()
                let headers = MarkdownSyntax.tableCells(in: line).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                let alignments = MarkdownSyntax.tableCells(in: lines[lineIndex + 1])
                    .map(MarkdownTableAlignment.init(dividerCell:))
                lineIndex += 2
                var rows: [[String]] = []
                while lineIndex < lines.count, MarkdownSyntax.isTableRow(lines[lineIndex]) {
                    rows.append(MarkdownSyntax.tableCells(in: lines[lineIndex]).map {
                        $0.trimmingCharacters(in: .whitespaces)
                    })
                    lineIndex += 1
                }
                append(.table(headers: headers, alignments: alignments, rows: rows))
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                append(.divider)
                lineIndex += 1
                continue
            }

            if let image = match(localImageRegex, in: trimmed),
               MarkdownAttachmentIndex.isSafeRelativePath(image[2]) {
                flushParagraph()
                append(.image(alt: image[1], relativePath: image[2]))
                lineIndex += 1
                continue
            }

            if let calloutMatch = match(calloutMarkerRegex, in: trimmed),
               let kind = MarkdownCalloutKind(calloutMatch[1]) {
                flushParagraph()
                let title = calloutMatch.indices.contains(2) ? calloutMatch[2].nilIfEmpty : nil
                lineIndex += 1
                var bodyLines: [String] = []
                while lineIndex < lines.count {
                    let nextLine = lines[lineIndex]
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.isEmpty { break }
                    if match(calloutMarkerRegex, in: nextTrimmed) != nil { break }
                    bodyLines.append(nextLine)
                    lineIndex += 1
                }
                append(.callout(MarkdownCallout(
                    kind: kind,
                    title: title,
                    body: Self.blocks(from: bodyLines.joined(separator: "\n"))
                )))
                continue
            }

            if let match = match(headingRegex, in: line) {
                flushParagraph()
                append(.heading(level: match[1].count, text: match[2]))
                lineIndex += 1
                continue
            }

            if let match = match(taskRegex, in: line) {
                flushParagraph()
                let checked = match[2].lowercased() == "x"
                append(.task(indent: indentLevel(match[1]), checked: checked, text: match[3]))
                lineIndex += 1
                continue
            }

            if let match = match(orderedRegex, in: line), let number = Int(match[2]) {
                flushParagraph()
                append(.ordered(indent: indentLevel(match[1]), number: number, text: match[3]))
                lineIndex += 1
                continue
            }

            if let match = match(bulletRegex, in: line) {
                flushParagraph()
                append(.bullet(indent: indentLevel(match[1]), text: match[2]))
                lineIndex += 1
                continue
            }

            if let strippedQuoteLine = stripOneQuoteLevel(from: line) {
                flushParagraph()
                var quotedLines = [strippedQuoteLine]
                lineIndex += 1
                while lineIndex < lines.count,
                      let stripped = stripOneQuoteLevel(from: lines[lineIndex]) {
                    quotedLines.append(stripped)
                    lineIndex += 1
                }
                let quotedBlocks = Self.blocks(from: quotedLines.joined(separator: "\n"))
                if quotedBlocks.count == 1, case .callout = quotedBlocks[0].kind {
                    append(quotedBlocks[0].kind)
                } else {
                    append(.quote(quotedBlocks))
                }
                continue
            }

            if let match = match(standaloneLinkRegex, in: trimmed),
               let url = URL(string: match[2]) {
                if MarkdownBodyView.rendersStandaloneLinkAsCard(destination: match[2]) {
                    flushParagraph()
                    append(.linkCard(label: match[1], url: url))
                } else {
                    paragraphLines.append(trimmed)
                }
                lineIndex += 1
                continue
            }

            paragraphLines.append(trimmed)
            lineIndex += 1
        }

        flushParagraph()
        return blocks
    }

    private static func match(_ regex: NSRegularExpression, in line: String) -> [String]? {
        let ns = line as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard let result = regex.firstMatch(in: line, range: fullRange) else { return nil }
        return (0..<result.numberOfRanges).map { index in
            let range = result.range(at: index)
            guard range.location != NSNotFound else { return "" }
            return ns.substring(with: range)
        }
    }

    private static func stripOneQuoteLevel(from line: String) -> String? {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " {
            index = line.index(after: index)
        }
        guard index < line.endIndex, line[index] == ">" else { return nil }
        index = line.index(after: index)
        if index < line.endIndex, line[index] == " " {
            index = line.index(after: index)
        }
        return String(line[index...])
    }

    private static func indentLevel(_ whitespace: String) -> Int {
        whitespace.reduce(0) { count, character in
            count + (character == "\t" ? 2 : 1)
        } / 2
    }
}

private enum SemanticMarkdownInlineRenderer {
    private struct Style {
        var bold = false
        var italic = false
        var strike = false
        var code = false
        var math = false
        var highlight = false
        var link: URL?
    }

    static func attributedString(for source: String, baseFont: Font = .body) -> AttributedString {
        parse(source, style: Style(), baseFont: baseFont)
    }

    private static func parse(_ source: String, style: Style, baseFont: Font) -> AttributedString {
        var result = AttributedString()
        var index = source.startIndex

        while index < source.endIndex {
            if source[index...].hasPrefix("<mark data-color=\""),
               let tagEnd = source[index...].firstIndex(of: ">"),
               let closeRange = source[source.index(after: tagEnd)...].range(of: "</mark>") {
                var highlighted = style
                highlighted.highlight = true
                let inner = String(source[source.index(after: tagEnd)..<closeRange.lowerBound])
                result += parse(inner, style: highlighted, baseFont: baseFont)
                index = closeRange.upperBound
                continue
            }

            if source[index...].hasPrefix("=="),
               let parsed = parseDelimited(source, from: index, marker: "==", style: style, baseFont: baseFont, transform: { current in
                   var next = current
                   next.highlight = true
                   return next
               }) {
                result += parsed.value
                index = parsed.nextIndex
                continue
            }

            if source[index...].hasPrefix("***"),
               let parsed = parseDelimited(source, from: index, marker: "***", style: style, baseFont: baseFont, transform: { current in
                   var next = current
                   next.bold = true
                   next.italic = true
                   return next
               }) {
                result += parsed.value
                index = parsed.nextIndex
                continue
            }

            if source[index...].hasPrefix("___"),
               let parsed = parseDelimited(source, from: index, marker: "___", style: style, baseFont: baseFont, transform: { current in
                   var next = current
                   next.bold = true
                   next.italic = true
                   return next
               }) {
                result += parsed.value
                index = parsed.nextIndex
                continue
            }

            if source[index...].hasPrefix("**"),
               let parsed = parseDelimited(source, from: index, marker: "**", style: style, baseFont: baseFont, transform: { current in
                   var next = current
                   next.bold = true
                   return next
               }) {
                result += parsed.value
                index = parsed.nextIndex
                continue
            }

            if source[index...].hasPrefix("~~"),
               let parsed = parseDelimited(source, from: index, marker: "~~", style: style, baseFont: baseFont, transform: { current in
                   var next = current
                   next.strike = true
                   return next
               }) {
                result += parsed.value
                index = parsed.nextIndex
                continue
            }

            if source[index...].hasPrefix("`"),
               let parsed = parseDelimited(source, from: index, marker: "`", style: style, baseFont: baseFont, transform: { current in
                   var next = current
                   next.code = true
                   return next
               }) {
                result += parsed.value
                index = parsed.nextIndex
                continue
            }

            if source[index...].hasPrefix("$"),
               !source[index...].hasPrefix("$$"),
               let parsed = parseDelimited(source, from: index, marker: "$", style: style, baseFont: baseFont, transform: { current in
                   var next = current
                   next.math = true
                   return next
               }) {
                result += parsed.value
                index = parsed.nextIndex
                continue
            }

            if source[index...].hasPrefix("*"),
               !source[index...].hasPrefix("**"),
               let parsed = parseDelimited(source, from: index, marker: "*", style: style, baseFont: baseFont, transform: { current in
                   var next = current
                   next.italic = true
                   return next
               }) {
                result += parsed.value
                index = parsed.nextIndex
                continue
            }

            if source[index] == "[",
               let parsed = parseLink(source, from: index, style: style, baseFont: baseFont) {
                result += parsed.value
                index = parsed.nextIndex
                continue
            }

            let runEnd = nextSpecialCharacter(in: source, after: index)
            append(String(source[index..<runEnd]), style: style, baseFont: baseFont, to: &result)
            index = runEnd
        }

        return result
    }

    private static func parseDelimited(_ source: String,
                                       from index: String.Index,
                                       marker: String,
                                       style: Style,
                                       baseFont: Font,
                                       transform: (Style) -> Style) -> (value: AttributedString, nextIndex: String.Index)? {
        let contentStart = source.index(index, offsetBy: marker.count)
        guard contentStart <= source.endIndex,
              let closeRange = source[contentStart...].range(of: marker) else {
            return nil
        }
        let inner = String(source[contentStart..<closeRange.lowerBound])
        return (parse(inner, style: transform(style), baseFont: baseFont), closeRange.upperBound)
    }

    private static func parseLink(_ source: String,
                                  from index: String.Index,
                                  style: Style,
                                  baseFont: Font) -> (value: AttributedString, nextIndex: String.Index)? {
        guard let closeBracket = source[index...].firstIndex(of: "]") else { return nil }
        let parenStart = source.index(after: closeBracket)
        guard parenStart < source.endIndex, source[parenStart] == "(" else { return nil }
        let destinationStart = source.index(after: parenStart)
        guard let destinationEnd = source[destinationStart...].firstIndex(of: ")") else { return nil }

        var linked = style
        linked.link = URL(string: String(source[destinationStart..<destinationEnd]))
        let label = String(source[source.index(after: index)..<closeBracket])
        return (parse(label, style: linked, baseFont: baseFont), source.index(after: destinationEnd))
    }

    private static func append(_ text: String,
                               style: Style,
                               baseFont: Font,
                               to result: inout AttributedString) {
        guard !text.isEmpty else { return }
        var attributed = AttributedString(text)

        if style.code || style.math {
            var font = Font.system(.body, design: .monospaced)
            if style.bold { font = font.bold() }
            if style.italic { font = font.italic() }
            attributed.font = font
            attributed.backgroundColor = Color(.tertiarySystemFill)
            if style.math {
                attributed.foregroundColor = .secondary
            }
        } else if style.bold || style.italic {
            var font = baseFont
            if style.bold { font = font.bold() }
            if style.italic { font = font.italic() }
            attributed.font = font
        } else {
            attributed.font = baseFont
        }

        if style.strike {
            attributed.strikethroughStyle = .single
        }
        if style.highlight {
            attributed.backgroundColor = ListsTokens.Markdown.highlight
            attributed.foregroundColor = ListsTokens.Markdown.highlightForeground
        }
        if let link = style.link {
            attributed.link = link
            attributed.foregroundColor = ListsTokens.accent
            attributed.underlineStyle = .single
        }

        result += attributed
    }

    private static func nextSpecialCharacter(in source: String, after index: String.Index) -> String.Index {
        var current = source.index(after: index)
        while current < source.endIndex {
            switch source[current] {
            case "=", "<", "*", "~", "`", "[", "$":
                return current
            default:
                current = source.index(after: current)
            }
        }
        return source.endIndex
    }
}
