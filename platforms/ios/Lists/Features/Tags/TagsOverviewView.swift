import SwiftUI

/// Top-level Tags screen — every tag in use, with counts. Tap a tag to drill
/// into items carrying it.
struct TagsOverviewView: View {
    let store: ItemStore

    var body: some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()

            ScrollView {
                if tagCounts.isEmpty {
                    ContentUnavailableView(
                        "No tags yet",
                        systemImage: "tag",
                        description: Text("Add `#tag` to an item's title or use the tag chip in the detail sheet.")
                    )
                    .padding(.top, ListsSpacing.s8)
                } else {
                    insetCard {
                        ForEach(Array(tagCounts.enumerated()), id: \.element.0) { idx, pair in
                            NavigationLink(value: TagDestination(name: pair.0)) {
                                tagRow(name: pair.0, count: pair.1)
                            }
                            .buttonStyle(.plain)
                            if idx < tagCounts.count - 1 {
                                Divider()
                                    .background(ListsTokens.Separator.translucent)
                                    .padding(.leading, 50)
                            }
                        }
                    }
                    .padding(.horizontal, ListsSpacing.s4)
                    .padding(.top, ListsSpacing.s4)
                    .padding(.bottom, ListsSpacing.s8)
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: TagDestination.self) { dest in
            TaggedItemsView(store: store, tag: dest.name)
        }
    }

    private func tagRow(name: String, count: Int) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "tag.fill", hue: ListsTokens.accentTintFg)
            Text("#\(name)")
                .font(ListsTypography.callout)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Spacer()
            Text("\(count)")
                .font(ListsTypography.mono)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func insetCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
                .fill(ListsTokens.Background.elevated)
        )
    }

    /// `[(tag, count)]` sorted by count descending, then alphabetical.
    private var tagCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in store.items where item.deletedAt == nil {
            for tag in item.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map { ($0.key, $0.value) }
    }
}

/// Hashable value used by NavigationStack for "items with this tag" routing.
public struct TagDestination: Hashable, Sendable {
    public let name: String
}
