import SwiftUI

struct CVSubListsHeaderRow: View {
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Sublists")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { onToggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse sublists" : "Expand sublists")
            .accessibilityIdentifier("list.sublists.chevron")
        }
        .padding(.leading, ListDetailLayout.leadingEdge)
        .padding(.trailing, ListDetailLayout.trailingEdge)
        .padding(.vertical, 2)
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
                IconBadge(
                    systemName: child.icon,
                    hue: ListsTokens.listColor(child.color),
                    shape: .circle
                )
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
            .padding(.vertical, 2)
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
