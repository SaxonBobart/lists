import SwiftUI

struct DocumentNavigatorSheet: View {
    let currentItemId: UUID
    let title: String
    let bodyText: String
    let items: [Item]
    let lists: [ItemList]
    let documentFileNames: [UUID: String]
    let onClose: () -> Void
    let onSelectOutline: (DocumentOutlineEntry) -> Void
    let onOpenLink: (DocumentLinkEntry) -> Void
    let onOpenBacklink: (DocumentBacklinkEntry) -> Void
    let onSelectFindResult: (DocumentFindResult) -> Void

    @State private var selectedTab: DocumentNavigatorTab = .outline
    @State private var findText = ""

    private var outline: [DocumentOutlineEntry] {
        DocumentMarkdownIndex.outline(title: title, body: bodyText)
    }

    private var links: [DocumentLinkEntry] {
        guard let source = items.first(where: { $0.id == currentItemId }) else { return [] }
        var current = source
        current.title = title
        current.body = bodyText
        return DocumentMarkdownIndex.links(
            in: current,
            items: items,
            lists: lists,
            documentFileNames: documentFileNames
        )
    }

    private var backlinks: [DocumentBacklinkEntry] {
        DocumentMarkdownIndex.backlinks(
            to: currentItemId,
            items: items,
            lists: lists,
            documentFileNames: documentFileNames
        )
    }

    private var findResults: [DocumentFindResult] {
        DocumentMarkdownIndex.find(findText, title: title, body: bodyText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                    .padding(.horizontal, ListsSpacing.s5)
                    .padding(.top, ListsSpacing.s4)
                    .padding(.bottom, ListsSpacing.s5)

                Group {
                    switch selectedTab {
                    case .outline:
                        outlineView
                    case .links:
                        linksView
                    case .find:
                        findView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(ListsTokens.Background.base)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton {
                        onClose()
                    }
                    .accessibilityIdentifier("document.navigator.close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DocumentNavigatorTab.allCases) { tab in
                Button {
                    withAnimation(.smooth) { selectedTab = tab }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.title3.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(Color(.systemFill))
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if tab.count(outline: outline.count, links: links.count + backlinks.count) > 0 {
                                Text("\(tab.count(outline: outline.count, links: links.count + backlinks.count))")
                                    .font(ListsTypography.caption1.bold())
                                    .foregroundStyle(ListsTokens.Foreground.secondary)
                                    .padding(.top, 3)
                                    .padding(.trailing, 16)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.accessibilityLabel)
                .accessibilityIdentifier("document.navigator.\(tab.rawValue)")
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
    }

    private var outlineView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListsSpacing.s4) {
                HStack(spacing: ListsSpacing.s2) {
                    Text("Contents")
                        .font(ListsTypography.title3.bold())
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                    Text("\(outline.count)")
                        .font(ListsTypography.caption1.bold())
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .padding(.horizontal, ListsSpacing.s5)

                VStack(alignment: .leading, spacing: ListsSpacing.s3) {
                    ForEach(outline) { entry in
                        Button {
                            onSelectOutline(entry)
                        } label: {
                            HStack(spacing: ListsSpacing.s3) {
                                Rectangle()
                                    .fill(ListsTokens.accent)
                                    .frame(width: 3, height: 24)
                                    .clipShape(Capsule())
                                    .opacity(entry.target == .title || entry.level == 1 ? 1 : 0)

                                Text(entry.title)
                                    .font(entry.target == .title ? ListsTypography.title3 : ListsTypography.body)
                                    .foregroundStyle(ListsTokens.Foreground.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)
                            }
                            .padding(.leading, CGFloat(max(0, entry.level - 1)) * 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, ListsSpacing.s5)
            }
            .padding(.top, ListsSpacing.s2)
        }
    }

    @ViewBuilder
    private var linksView: some View {
        if links.isEmpty, backlinks.isEmpty {
            VStack(spacing: ListsSpacing.s3) {
                Image(systemName: "link")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                Text("No Links")
                    .font(ListsTypography.title3.bold())
                    .foregroundStyle(ListsTokens.Foreground.primary)
                Text("Links to and from this document\nwill appear here.")
                    .font(ListsTypography.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 180)
        } else {
            List {
                if links.isEmpty == false {
                    Section("From this document") {
                        ForEach(links) { link in
                            Button { onOpenLink(link) } label: { linkRow(link) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("document.navigator.link.\(link.id)")
                        }
                    }
                }

                if backlinks.isEmpty == false {
                    Section("Links to this document") {
                        ForEach(backlinks) { backlink in
                            Button { onOpenBacklink(backlink) } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(backlink.sourceTitle)
                                            .font(ListsTypography.body.weight(.semibold))
                                            .foregroundStyle(ListsTokens.Foreground.primary)
                                            .lineLimit(1)
                                        Text(backlink.context)
                                            .font(ListsTypography.footnote)
                                            .foregroundStyle(ListsTokens.Foreground.secondary)
                                            .lineLimit(2)
                                    }
                                } icon: {
                                    Image(systemName: "arrow.turn.up.left")
                                        .foregroundStyle(ListsTokens.accent)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("document.navigator.backlink.\(backlink.id)")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func linkRow(_ link: DocumentLinkEntry) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(link.label)
                    .font(ListsTypography.body)
                    .foregroundStyle(ListsTokens.Foreground.primary)
                    .lineLimit(1)
                Text(link.subtitle)
                    .font(ListsTypography.footnote)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: link.icon)
                .foregroundStyle(link.tint)
        }
    }

    private var findView: some View {
        VStack(spacing: 0) {
            HStack(spacing: ListsSpacing.s2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                TextField("Find in Document", text: $findText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, ListsSpacing.s4)
            .frame(height: 44)
            .background(Color(.secondarySystemFill), in: Capsule())
            .padding(.horizontal, ListsSpacing.s5)
            .padding(.bottom, ListsSpacing.s4)

            if findText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Find in document", systemImage: "magnifyingglass")
            } else if findResults.isEmpty {
                ContentUnavailableView.search(text: findText)
            } else {
                List(findResults) { result in
                    Button {
                        onSelectFindResult(result)
                    } label: {
                        Text(result.excerpt)
                            .font(ListsTypography.body)
                            .foregroundStyle(ListsTokens.Foreground.primary)
                            .lineLimit(2)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private enum DocumentNavigatorTab: String, CaseIterable, Identifiable {
    case outline
    case links
    case find

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .outline: return "list.bullet"
        case .links: return "link"
        case .find: return "magnifyingglass"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .outline: return "Contents"
        case .links: return "Links"
        case .find: return "Find"
        }
    }

    func count(outline: Int, links: Int) -> Int {
        switch self {
        case .outline: return outline
        case .links: return links
        case .find: return 0
        }
    }
}

private extension DocumentLinkEntry {
    var icon: String {
        switch destination {
        case .internalItem: return "doc.text"
        case .external: return "safari"
        case .unresolved: return "questionmark.circle"
        }
    }

    var tint: Color {
        switch destination {
        case .internalItem: return ListsTokens.accent
        case .external: return .blue
        case .unresolved: return ListsTokens.Foreground.secondary
        }
    }
}
