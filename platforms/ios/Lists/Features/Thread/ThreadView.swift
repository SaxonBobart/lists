import SwiftUI

/// Thread view per PRODUCT-SPEC.md §2.4 — flattens an item + its children +
/// grandchildren into one continuous read document, using H1/H2/H3 hierarchy.
///
/// Read-only first pass: titles + body render as static markdown-ish text.
/// In-line editing within the thread is a follow-up.
struct ThreadView: View {
    let root: Item
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListsSpacing.s5) {
                heading(root, level: 1)
                if !trimmed(root.body).isEmpty {
                    body(root)
                }

                ForEach(children(of: root.id), id: \.id) { child in
                    VStack(alignment: .leading, spacing: ListsSpacing.s3) {
                        heading(child, level: 2)
                        if !trimmed(child.body).isEmpty {
                            body(child)
                        }
                        ForEach(children(of: child.id), id: \.id) { grand in
                            VStack(alignment: .leading, spacing: ListsSpacing.s2) {
                                heading(grand, level: 3)
                                if !trimmed(grand.body).isEmpty {
                                    body(grand)
                                }
                            }
                            .padding(.leading, ListsSpacing.s5)
                        }
                    }
                    .padding(.leading, ListsSpacing.s4)
                }

                Spacer().frame(height: ListsSpacing.s8)
            }
            .padding(.horizontal, ListsSpacing.s5)
            .padding(.top, ListsSpacing.s4)
        }
        .background(ListsTokens.Background.grouped)
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Heading + body

    @ViewBuilder
    private func heading(_ item: Item, level: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            checkbox(for: item)
            Text(item.title)
                .font(headingFont(level))
                .foregroundStyle(item.done
                                 ? ListsTokens.Foreground.tertiary
                                 : ListsTokens.Foreground.primary)
                .strikethrough(item.done, color: ListsTokens.Foreground.tertiary)
        }
    }

    private func body(_ item: Item) -> some View {
        Text(trimmed(item.body))
            .font(ListsTypography.body)
            .foregroundStyle(ListsTokens.Foreground.secondary)
            .padding(.leading, 36)
    }

    private func checkbox(for item: Item) -> some View {
        Button {
            Task { try? await store.toggleDone(item.id) }
        } label: {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(item.done
                                 ? ListsTokens.accent
                                 : ListsTokens.Foreground.tertiary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return ListsTypography.title1
        case 2: return ListsTypography.title3
        default: return ListsTypography.headline
        }
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func children(of id: UUID) -> [Item] {
        store.items
            .filter { $0.parentId == id && $0.deletedAt == nil }
            .sorted { lhs, rhs in
                (lhs.due ?? .distantFuture) < (rhs.due ?? .distantFuture)
            }
    }
}
