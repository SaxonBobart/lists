import SwiftUI

/// Single user-list view (vertical layout). Items grouped by section if any
/// are set; otherwise flat. Uses SwiftUI `List` with `.insetGrouped` for
/// native iOS chrome.
///
/// FloatingAddButton at bottom-right: tap → QuickCaptureSheet for this list;
/// drag onto a section header → QuickCaptureSheet pre-targeted to that section.
struct ListDetailView: View {
    let store: ItemStore
    let list: ItemList

    @State private var captureTarget: CaptureTarget?
    @State private var dropFrames: [DropTargetFrame] = []
    @State private var hoveredId: String?
    @State private var fabIsInteracting = false

    private static let sectionPrefix = "section:"

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemBackground).ignoresSafeArea()

            if visibleItems.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sections, id: \.self) { section in
                        sectionView(section)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(fabIsInteracting)
                .onPreferenceChange(DropTargetFrameKey.self) { dropFrames = $0 }
            }

            FloatingAddButton(
                tint: ListsTokens.listColor(list.color),
                action: {
                    captureTarget = CaptureTarget(listId: list.id, section: nil)
                },
                onDragChanged: { location in
                    let hit = dropFrames.first { $0.rect.contains(location) }
                    if hoveredId != hit?.id {
                        hoveredId = hit?.id
                    }
                },
                onDragEnded: { location in
                    if let hit = dropFrames.first(where: { $0.rect.contains(location) }),
                       let section = parseSection(hit.id) {
                        captureTarget = CaptureTarget(listId: list.id, section: section)
                    } else {
                        captureTarget = CaptureTarget(listId: list.id, section: nil)
                    }
                    hoveredId = nil
                },
                isInteracting: $fabIsInteracting
            )
            .padding(.trailing, 16)
            .padding(.bottom, 0)
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .tint(ListsTokens.listColor(list.color))
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(store: store, defaultListId: target.listId, defaultSection: target.section)
        }
    }

    // MARK: - Section view

    @ViewBuilder
    private func sectionView(_ name: String) -> some View {
        let entries = items(in: name)
        if !entries.isEmpty {
            Section {
                let rows = flatten(entries)
                ForEach(Array(rows.enumerated()), id: \.element.item.id) { idx, row in
                    ItemRow(
                        item: row.item,
                        isOverdue: isOverdue(row.item),
                        store: store,
                        onToggle: { Task { try? await store.toggleDone(row.item.id) } },
                        indent: row.indent,
                        previousSiblingId: idx > 0 ? rows[idx - 1].item.id : nil
                    )
                }
            } header: {
                if name != Self.uncategorized {
                    HStack {
                        Text(name.uppercased())
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .background(
                        // Drop-target hit area covers the whole section header.
                        Color.clear
                            .overlay(
                                hoveredId == Self.sectionPrefix + name
                                ? Rectangle().fill(ListsTokens.listColor(list.color).opacity(0.18))
                                    .padding(-8)
                                : nil
                            )
                    )
                    .dropTarget(Self.sectionPrefix + name)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No items yet", systemImage: list.icon)
        } description: {
            Text("Tap or drag the + button to add one.")
        }
    }

    // MARK: - Data

    private static let uncategorized = "__uncategorized__"

    /// Top-level items in this list; children render under parents.
    private var visibleItems: [Item] {
        store.items
            .filter { $0.listId == list.id && !$0.done && $0.deletedAt == nil && $0.parentId == nil }
    }

    private var sections: [String] {
        var seen: [String] = []
        var sawUncategorized = false
        for item in visibleItems {
            if let s = item.section {
                if !seen.contains(s) { seen.append(s) }
            } else {
                sawUncategorized = true
            }
        }
        return (sawUncategorized ? [Self.uncategorized] : []) + seen
    }

    private func items(in section: String) -> [Item] {
        if section == Self.uncategorized {
            return visibleItems.filter { $0.section == nil }
        }
        return visibleItems.filter { $0.section == section }
    }

    private func flatten(_ parents: [Item]) -> [(item: Item, indent: Int)] {
        var out: [(Item, Int)] = []
        for parent in parents {
            out.append((parent, 0))
            for child in childrenOf(parent.id) {
                out.append((child, 1))
                for g in childrenOf(child.id) {
                    out.append((g, 2))
                }
            }
        }
        return out
    }

    private func childrenOf(_ id: UUID) -> [Item] {
        store.items
            .filter { $0.parentId == id && $0.deletedAt == nil && !$0.done }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    private func isOverdue(_ item: Item) -> Bool {
        guard let due = item.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    private func parseSection(_ id: String) -> String? {
        guard id.hasPrefix(Self.sectionPrefix) else { return nil }
        let s = String(id.dropFirst(Self.sectionPrefix.count))
        return s == Self.uncategorized ? nil : s
    }
}
