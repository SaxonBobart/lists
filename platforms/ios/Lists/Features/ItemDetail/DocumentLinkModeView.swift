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
        markdownLink(label: rawLabel, destination: url.absoluteString)
    }

    static func markdownLink(label rawLabel: String, destination: String) -> String {
        let label = escapedLabel(rawLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? destination)
        return "[\(label)](\(destination))"
    }

    static func replacingSelection(_ selection: DocumentLinkEditorSelection,
                                   in body: String,
                                   label: String,
                                   url: URL) -> String {
        let valid = validSelection(selection.range, in: body)
        let ns = body as NSString
        return ns.replacingCharacters(in: valid, with: markdownLink(label: label, url: url))
    }

    static func replacement(_ selection: DocumentLinkEditorSelection,
                            in body: String,
                            label: String,
                            url: URL) -> (body: String, caretRange: NSRange) {
        let valid = validSelection(selection.range, in: body)
        let ns = body as NSString
        let inserted = markdownLink(label: label, url: url)
        return (
            ns.replacingCharacters(in: valid, with: inserted),
            NSRange(location: valid.location + (inserted as NSString).length, length: 0)
        )
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
}

@MainActor
@Observable
final class DocumentLinkSession {
    private(set) var source: DocumentLinkSource?
    private(set) var pendingTarget: Item?

    var isActive: Bool {
        source != nil
    }

    func begin(source: DocumentLinkSource) {
        pendingTarget = nil
        self.source = source
    }

    func cancel() {
        pendingTarget = nil
        source = nil
    }

    func cancelPendingTarget() {
        pendingTarget = nil
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
        let headings = headingOptions(for: target)
        if headings.isEmpty == false {
            pendingTarget = target
            return
        }
        commit(to: target, heading: nil, store: store)
    }

    func commit(to target: Item, heading: DocumentOutlineEntry?, store: ItemStore) {
        guard let source, canPick(target),
              var sourceItem = store.item(source.itemId),
              sourceItem.deletedAt == nil else {
            cancel()
            return
        }

        let selection = validSelection(source.selection.range, in: sourceItem.body)
        let selectedLabel = source.selection.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetTitle = target.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled"
        let label = DocumentMarkdownLinkBuilder.escapedLabel(selectedLabel.nilIfEmpty ?? heading?.title ?? targetTitle)
        let destination = DocumentMarkdownIndex.portableDestination(
            from: sourceItem,
            to: target,
            heading: heading?.title,
            lists: store.lists,
            documentFileNames: store.documentFileNamesById
        )
        let link = "[\(label)](\(destination))"
        let body = sourceItem.body as NSString
        sourceItem.body = body.replacingCharacters(in: selection, with: link)
        store.applyUpdateWithSubtreeCascadesSync(sourceItem)
        cancel()
    }

    func headingOptions(for item: Item) -> [DocumentOutlineEntry] {
        DocumentMarkdownIndex.outline(title: item.title, body: item.body).filter {
            if case .body = $0.target { return true }
            return false
        }
    }

    func cancelIfSourceUnavailable(in store: ItemStore) {
        guard let source else { return }
        guard let item = store.item(source.itemId), item.deletedAt == nil else {
            cancel()
            return
        }
        if let pendingTarget,
           store.item(pendingTarget.id)?.deletedAt != nil || store.item(pendingTarget.id) == nil {
            cancelPendingTarget()
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
            if session.source != nil, let target = session.pendingTarget {
                headingChooser(target: target)
            } else if let source = session.source {
                linkingStatus(source: source)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onAppear { session.cancelIfSourceUnavailable(in: store) }
        .onChange(of: sourceAvailabilityToken) { _, _ in
            session.cancelIfSourceUnavailable(in: store)
        }
    }

    private func linkingStatus(source: DocumentLinkSource) -> some View {
        let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled"
        return HStack(spacing: 12) {
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
        .accessibilityIdentifier("document.linkMode.shelf")
        .accessibilityHint("Open a list and tap the document to link.")
    }

    private func headingChooser(target: Item) -> some View {
        let targetTitle = target.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled"
        let headings = session.headingOptions(for: target)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button("Back", systemImage: "chevron.backward") {
                    session.cancelPendingTarget()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: 44, height: 44)
                .accessibilityIdentifier("document.linkMode.heading.back")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Link to")
                        .font(ListsTypography.caption1)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                    Text(targetTitle)
                        .font(ListsTypography.body.weight(.semibold))
                        .foregroundStyle(ListsTokens.Foreground.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Cancel", systemImage: "xmark") {
                    session.cancel()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: 44, height: 44)
                .accessibilityIdentifier("document.linkMode.cancel")
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    headingButton(title: "Whole item", systemImage: "doc.text") {
                        session.commit(to: target, heading: nil, store: store)
                    }
                    ForEach(headings) { heading in
                        headingButton(title: heading.title, systemImage: "number") {
                            session.commit(to: target, heading: heading, store: store)
                        }
                        .accessibilityIdentifier("document.linkMode.heading.\(heading.id)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("document.linkMode.headingChooser")
    }

    private func headingButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(ListsTypography.caption1.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var sourceAvailabilityToken: String {
        guard let source = session.source else { return "none" }
        guard let item = store.item(source.itemId) else { return "missing:\(source.itemId)" }
        let sourceToken = item.deletedAt == nil ? "active:\(source.itemId)" : "deleted:\(source.itemId)"
        guard let target = session.pendingTarget else { return sourceToken }
        let targetState = store.item(target.id)?.deletedAt == nil ? "active" : "missing"
        return "\(sourceToken):target:\(target.id):\(targetState)"
    }
}
