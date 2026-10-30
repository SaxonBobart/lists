import SwiftUI
import UIKit
import Observation

final class ListDetailPinnedHeaderCell: UICollectionViewListCell {
    private let columnScrollSeparator = UIView()
    private var separatorHeightConstraint: NSLayoutConstraint!

    var showsColumnScrollSeparator: Bool = false {
        didSet {
            columnScrollSeparator.isHidden = !showsColumnScrollSeparator
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureColumnScrollSeparator()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureColumnScrollSeparator()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        separatorHeightConstraint.constant = 1 / max(1, traitCollection.displayScale)
        columnScrollSeparator.backgroundColor = .separator
        bringSubviewToFront(columnScrollSeparator)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        showsColumnScrollSeparator = false
    }

    private func configureColumnScrollSeparator() {
        columnScrollSeparator.translatesAutoresizingMaskIntoConstraints = false
        columnScrollSeparator.backgroundColor = .separator
        columnScrollSeparator.isHidden = true
        columnScrollSeparator.isUserInteractionEnabled = false
        columnScrollSeparator.accessibilityIdentifier = "list.columns.header.separator"
        addSubview(columnScrollSeparator)
        separatorHeightConstraint = columnScrollSeparator.heightAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([
            columnScrollSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            columnScrollSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            columnScrollSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorHeightConstraint
        ])
    }
}

struct CVSubListsHeaderRow: View {
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { onToggle() }
        } label: {
            HStack(spacing: 8) {
                Text("Sublists")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .padding(.leading, ListDetailLayout.leadingEdge)
            .padding(.trailing, ListDetailLayout.trailingEdge)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Collapse sublists" : "Expand sublists")
        .accessibilityIdentifier("list.sublists.chevron")
    }
}

struct CVSubListChildRow: View {
    let child: ItemList
    let openItemCount: Int
    let onOpen: () -> Void

    var body: some View {
        // Plain Button + manual chevron (no NavigationLink): the system
        // disclosure indicator that NavigationLink draws sits at a different
        // trailing inset than the Sub-Lists header chevron above, so we
        // route the tap programmatically and draw a matching chevron at
        // trailing = leadingEdge to make the two share an x-position.
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.body)
                    .foregroundStyle(ListsTokens.listColor(child.color))
                    .frame(width: 22)
                Text(child.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(openItemCount)")
                    .font(ListsTypography.mono)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, ListDetailLayout.leadingEdge)
            .padding(.trailing, ListDetailLayout.trailingEdge)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CVSectionDropPlaceholder: View {
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(height: height)
            .contentShape(Rectangle())
    }
}

struct CVSectionHeaderRow: View {
    let sectionKey: String
    let displayName: String
    let isOthers: Bool
    let expanded: Bool
    let showTopDivider: Bool
    let listColor: Color
    var isColumn: Bool = false
    /// True for the `.editingSectionHeader` variant — open straight into the
    /// focused rename field (used by "New Section"). The placeholder shows the
    /// seeded name so an empty commit just keeps it.
    var startEditing: Bool = false
    let onToggleExpanded: () -> Void
    let onCommitRename: (String) -> Void
    /// Called when an inline rename finishes (commit or blur) so the host can
    /// clear `editingSectionKey`. No-op for tap-to-rename on a static header.
    var onEndEditing: () -> Void = {}

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        let color: Color = isOthers ? .secondary : .primary
        VStack(alignment: .leading, spacing: 8) {
            if showTopDivider {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 1)
                    .padding(.leading, ListDetailLayout.leadingEdge)
                    .padding(.trailing, ListDetailLayout.trailingEdge)
            }
            HStack(spacing: 8) {
                Group {
                    if isRenaming {
                        TextField(displayName, text: $renameText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(color)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($renameFocused)
                            .onSubmit(commit)
                            .onChange(of: renameFocused) { _, focused in
                                if !focused { commit() }
                            }
                            .accessibilityIdentifier("list.section.\(sectionKey).title")
                    } else {
                        Button(action: beginRename) {
                            Text(displayName)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(color)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("list.section.\(sectionKey).title")
                    }
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { onToggleExpanded() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse \(displayName)" : "Expand \(displayName)")
                .accessibilityIdentifier("list.section.\(sectionKey).chevron")
            }
            .padding(.leading, isColumn ? 14 : ListDetailLayout.leadingEdge)
            .padding(.trailing, isColumn ? 14 : ListDetailLayout.trailingEdge)
        }
        .padding(.top, isColumn ? 8 : 2)
        .padding(.bottom, isColumn ? 4 : 2)
        .onAppear {
            // The `.editingSectionHeader` variant opens straight into editing
            // with an empty field (the seeded name shows as the placeholder).
            if startEditing, !isRenaming {
                renameText = ""
                isRenaming = true
                DispatchQueue.main.async { renameFocused = true }
            }
        }
    }

    private func beginRename() {
        renameText = isOthers ? "" : displayName
        isRenaming = true
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commit() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onCommitRename(trimmed) }
        isRenaming = false
        onEndEditing()
    }
}

struct BrowseSubListsControl: View {
    let count: Int
    let onBrowse: () -> Void

    var body: some View {
        Button(action: onBrowse) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                Text("Browse sub-lists")
                Spacer()
                Text(count.formatted()).monospacedDigit()
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(.quaternary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ListDetailLayout.leadingEdge)
        .padding(.vertical, 6)
        .accessibilityLabel("Browse \(count) sub-lists")
        .accessibilityIdentifier("list.sublists.browse")
        .accessibilityHint("Pull down at the top to reveal sub-lists")
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.height >= 64 && value.translation.height > abs(value.translation.width) { onBrowse() }
        })
    }
}

struct SubListBrowserView: View {
    let parentName: String
    let rootID: String
    let lists: [ItemList]
    let counts: [String: Int]
    let onOpen: (ItemList) -> Void
    let onClose: () -> Void
    let onDelete: (String) -> Void
    @State private var collapsed = Set(UserDefaults.standard.stringArray(forKey: "sidebar.collapsed.v1") ?? [])

    private var rows: [ListHierarchy.FlatRow] {
        ListHierarchy.flattenedRows(in: lists, expanded: { !collapsed.contains($0) }, rootParentID: rootID)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sub-lists").font(.headline)
                    Text(parentName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(.glass)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("list.sublists.close")
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button { onOpen(row.list) } label: {
                            SidebarListCellContent(list: row.list, depth: row.depth,
                                hasChildren: row.hasChildren, isCollapsed: collapsed.contains(row.id),
                                count: counts[row.id] ?? 0)
                                .padding(.vertical, 7).padding(.horizontal, 16)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(row.list.name)
                        .accessibilityIdentifier("list.sublist.\(row.id.lowercased())")
                        .overlay(alignment: .trailing) {
                            if row.hasChildren {
                                Button {
                                    if collapsed.contains(row.id) { collapsed.remove(row.id) }
                                    else { collapsed.insert(row.id) }
                                    UserDefaults.standard.set(Array(collapsed).sorted(), forKey: "sidebar.collapsed.v1")
                                } label: {
                                    Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(collapsed.contains(row.id) ? "Expand \(row.list.name)" : "Collapse \(row.list.name)")
                                .accessibilityIdentifier("list.sublist.disclosure.\(row.id.lowercased())")
                                .padding(.trailing, 9)
                            }
                        }
                        .contextMenu {
                            Button("Delete sub-list", systemImage: "trash", role: .destructive) { onDelete(row.id) }
                                .accessibilityIdentifier("list.sublist.delete.\(row.id.lowercased())")
                        }
                        if row.id != rows.last?.id {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
            }
        }
        .padding(16)
        .background(Color(.systemGroupedBackground))
        .accessibilityAction(.escape, onClose)
    }
}

@MainActor @Observable
final class ListHierarchyRevealSession {
    var ownerID: String?
    var ownerName = ""
    var isRevealed = false
    @ObservationIgnored private var onOpen: ((ItemList) -> Void)?

    func reveal(list: ItemList, onOpen: @escaping (ItemList) -> Void) {
        ownerID = list.id
        ownerName = list.name
        self.onOpen = onOpen
        isRevealed = true
    }

    func close() { isRevealed = false }

    func select(_ list: ItemList) {
        close()
        onOpen?(list)
    }

    func leave(owner: String) {
        if ownerID == owner { close(); onOpen = nil }
    }
}

extension EnvironmentValues {
    @Entry var listHierarchyRevealSession: ListHierarchyRevealSession?
}

struct ListHierarchyRevealHost<Content: View>: View {
    let session: ListHierarchyRevealSession
    let store: ItemStore
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if let ownerID = session.ownerID {
                    SubListBrowserView(parentName: session.ownerName, rootID: ownerID, lists: store.lists,
                        counts: Dictionary(uniqueKeysWithValues: store.lists.map { ($0.id, store.openItemCount(in: $0.id)) }),
                        onOpen: session.select, onClose: session.close,
                        onDelete: { id in Task { try? await store.softDeleteList(id) } })
                        .frame(height: session.isRevealed ? min(320, max(180, geometry.size.height * 0.35)) : 0)
                        .clipped().allowsHitTesting(session.isRevealed)
                        .accessibilityHidden(!session.isRevealed)
                }
                Divider().frame(height: session.isRevealed ? 1 : 0).opacity(session.isRevealed ? 1 : 0)
                content.environment(\.listHierarchyRevealSession, session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).id("main-navigation")
            }
            .background(Color(.systemGroupedBackground))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: session.isRevealed)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in session.close() }
    }
}

enum ListHierarchyPullPolicy {
    static func shouldReveal(overscroll: CGFloat, horizontalVelocity: CGFloat, verticalVelocity: CGFloat, startedAtTop: Bool = true) -> Bool {
        startedAtTop && overscroll >= 64 && abs(verticalVelocity) >= abs(horizontalVelocity)
    }
}
