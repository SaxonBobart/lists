import SwiftUI
import Observation

struct DocumentLinkEditorSelection {
    let range: NSRange
    let selectedText: String
}

struct DocumentLinkSource {
    let itemId: UUID
    let title: String
    let selection: DocumentLinkEditorSelection
}

enum DocumentMarkdownLinkBuilder {
    static func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              url.scheme != nil,
              (url.host?.isEmpty == false || url.scheme == "mailto") else {
            return nil
        }
        return url
    }

    static func markdownLink(label rawLabel: String, url: URL) -> String {
        let label = escapedLabel(rawLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url.absoluteString)
        return "[\(label)](\(url.absoluteString))"
    }

    static func replacingSelection(_ selection: DocumentLinkEditorSelection,
                                   in body: String,
                                   label: String,
                                   url: URL) -> String {
        let valid = validSelection(selection.range, in: body)
        let ns = body as NSString
        let prefix = needsLeadingNewline(before: valid, in: body) ? "\n" : ""
        return ns.replacingCharacters(in: valid, with: prefix + markdownLink(label: label, url: url))
    }

    static func escapedLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: #"\["#)
            .replacingOccurrences(of: "]", with: #"\]"#)
    }

    static func validSelection(_ selection: NSRange, in body: String) -> NSRange {
        let length = (body as NSString).length
        guard selection.location != NSNotFound,
              selection.location >= 0,
              selection.length >= 0,
              NSMaxRange(selection) <= length else {
            return NSRange(location: length, length: 0)
        }
        return selection
    }

    static func needsLeadingNewline(before selection: NSRange, in body: String) -> Bool {
        selection.length == 0
            && selection.location == (body as NSString).length
            && !body.isEmpty
            && !body.hasSuffix("\n")
    }
}

@MainActor
@Observable
final class DocumentLinkSession {
    private(set) var source: DocumentLinkSource?

    var isActive: Bool {
        source != nil
    }

    func begin(source: DocumentLinkSource) {
        self.source = source
    }

    func cancel() {
        source = nil
    }

    func canPick(_ item: Item) -> Bool {
        guard let source,
              item.deletedAt == nil,
              item.type != .habit else {
            return false
        }
        return item.id != source.itemId
    }

    func commit(to target: Item, store: ItemStore) {
        guard let source, canPick(target),
              var sourceItem = store.item(source.itemId),
              sourceItem.deletedAt == nil else {
            cancel()
            return
        }

        let selection = validSelection(source.selection.range, in: sourceItem.body)
        let selectedLabel = source.selection.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetTitle = target.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled"
        let label = DocumentMarkdownLinkBuilder.escapedLabel(selectedLabel.nilIfEmpty ?? targetTitle)
        let link = "[\(label)](\(DocumentMarkdownIndex.internalLinkURL(for: target.id).absoluteString))"
        let body = sourceItem.body as NSString
        let prefix = DocumentMarkdownLinkBuilder.needsLeadingNewline(before: selection, in: sourceItem.body) ? "\n" : ""
        sourceItem.body = body.replacingCharacters(in: selection, with: prefix + link)
        store.applyUpdateWithSubtreeCascadesSync(sourceItem)
        cancel()
    }

    func cancelIfSourceUnavailable(in store: ItemStore) {
        guard let source else { return }
        guard let item = store.item(source.itemId), item.deletedAt == nil else {
            cancel()
            return
        }
    }

    private func validSelection(_ selection: NSRange, in body: String) -> NSRange {
        DocumentMarkdownLinkBuilder.validSelection(selection, in: body)
    }
}

struct DocumentLinkShelfView: View {
    let session: DocumentLinkSession
    let store: ItemStore

    var body: some View {
        Group {
            if let source = session.source {
                let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled"
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .font(.headline)
                        .foregroundStyle(ListsTokens.accent)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Linking from")
                            .font(ListsTypography.caption1)
                            .foregroundStyle(ListsTokens.Foreground.secondary)
                        Text(title)
                            .font(ListsTypography.body.weight(.semibold))
                            .foregroundStyle(ListsTokens.Foreground.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Linking from")
                    .accessibilityValue(title)

                    Button("Cancel", systemImage: "xmark") {
                        session.cancel()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Cancel document link")
                    .accessibilityIdentifier("document.linkMode.cancel")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("document.linkMode.shelf")
                .accessibilityHint("Open a list and tap the document to link.")
            }
        }
        .onAppear { session.cancelIfSourceUnavailable(in: store) }
        .onChange(of: sourceAvailabilityToken) { _, _ in
            session.cancelIfSourceUnavailable(in: store)
        }
    }

    private var sourceAvailabilityToken: String {
        guard let source = session.source else { return "none" }
        guard let item = store.item(source.itemId) else { return "missing:\(source.itemId)" }
        return item.deletedAt == nil ? "active:\(source.itemId)" : "deleted:\(source.itemId)"
    }
}
