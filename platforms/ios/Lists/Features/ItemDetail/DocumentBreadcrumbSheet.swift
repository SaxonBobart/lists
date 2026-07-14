import SwiftUI

/// Navigation value for the breadcrumb menu. It pushes another item's document
/// page onto the hosting detail stack.
struct BreadcrumbDestination: Hashable {
    let id: UUID
    let heading: String?

    init(id: UUID, heading: String? = nil) {
        self.id = id
        self.heading = heading
    }
}

struct DocumentBreadcrumbSheet: View {
    let current: Item
    let ancestors: [Item]
    let children: [Item]
    let onSelect: (UUID) -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(ancestors.enumerated()), id: \.element.id) { index, ancestor in
                    Button {
                        onSelect(ancestor.id)
                    } label: {
                        breadcrumbRow(ancestor, depth: index, isCurrent: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("document.breadcrumb.ancestor.\(ancestor.id.uuidString)")
                }

                breadcrumbRow(current, depth: ancestors.count, isCurrent: true)
                    .accessibilityIdentifier("document.breadcrumb.current")

                ForEach(children) { child in
                    Button {
                        onSelect(child.id)
                    } label: {
                        breadcrumbRow(child, depth: ancestors.count + 1, isCurrent: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("document.breadcrumb.child.\(child.id.uuidString)")
                }
            }
            .navigationTitle("Breadcrumb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .tint(.primary)
                        .accessibilityIdentifier("document.breadcrumb.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func breadcrumbRow(_ item: Item, depth: Int, isCurrent: Bool) -> some View {
        HStack(spacing: 8) {
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * 16)
                Image(systemName: "arrow.turn.down.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            Text(label(for: item))
                .foregroundStyle(isCurrent ? ListsTokens.Foreground.secondary
                                           : ListsTokens.Foreground.primary)
            Spacer()
            if isCurrent {
                Text("Current")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func label(for item: Item) -> String {
        item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : item.title
    }
}
