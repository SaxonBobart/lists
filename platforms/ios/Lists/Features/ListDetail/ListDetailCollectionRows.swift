import SwiftUI
import UIKit

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
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
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
    }
}

struct SubListBrowserView: View {
    let parentName: String
    let children: [ItemList]
    let counts: [String: Int]
    let onOpen: (ItemList) -> Void
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(parentName).font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(children) { child in
                            Button {
                                dismiss()
                                onOpen(child)
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .font(.title2)
                                            .foregroundStyle(ListsTokens.listColor(child.color))
                                        Spacer()
                                        Image(systemName: "arrow.up.right").font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(child.name).font(.headline).foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: 4) {
                                        Text((counts[child.id] ?? 0).formatted()).monospacedDigit()
                                        Text((counts[child.id] ?? 0) == 1 ? "open item" : "open items")
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                                .padding(16)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("list.sublist.\(child.id.lowercased())")
                            .contextMenu {
                                Button("Delete sub-list", systemImage: "trash", role: .destructive) { onDelete(child.id) }
                                    .accessibilityIdentifier("list.sublist.delete.\(child.id.lowercased())")
                            }
                        }
                    }
                }.padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sub-lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("list.sublists.close")
                }
            }
        }
    }
}
