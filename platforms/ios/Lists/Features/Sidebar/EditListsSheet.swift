import SwiftUI

/// Edit Lists sheet — manages the sidebar's pinned section: auto-list
/// visibility + order, plus the Tags row toggle.
///
/// Two sections:
/// 1. **Auto-Lists**: each row has a leading checkbox + drag handle.
///    Uncheck → hides the tile in the sidebar; reordering controls
///    sidebar tile order.
/// 2. **Tags**: single toggle row. Uncheck → hides the Tags row from
///    My Lists.
///
/// User-list reordering, deletion, and editing now live on the sidebar
/// itself (pencil-button reorder mode + swipe actions + long-press
/// context menu) and are no longer surfaced here.
struct EditListsSheet: View {
    let store: ItemStore
    @Bindable var autoListPrefs: AutoListPreferences

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                autoListsSection
                tagsSection
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Pinned Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("Done")
                    }
                }
            }
        }
    }

    // MARK: - Auto-lists section

    private var autoListsSection: some View {
        Section {
            ForEach(autoListPrefs.order) { smartList in
                let visible = !autoListPrefs.hidden.contains(smartList)
                HStack(spacing: 12) {
                    Button {
                        autoListPrefs.setHidden(smartList, visible)
                    } label: {
                        Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(visible ? ListsTokens.accent : Color.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    IconBadge(
                        systemName: smartList.iconName,
                        hue: ListsTokens.smartColor(smartList),
                        shape: .circle
                    )
                    Text(smartList.displayName)
                    Spacer()
                }
            }
            .onMove { source, destination in
                autoListPrefs.move(fromOffsets: source, toOffset: destination)
            }
        } header: {
            Text("Auto-Lists")
        } footer: {
            Text("Auto-lists are stuck at the top. Uncheck to hide.")
        }
    }

    // MARK: - Tags toggle

    private var tagsSection: some View {
        Section {
            let visible = !autoListPrefs.tagsHidden
            HStack(spacing: 12) {
                Button {
                    autoListPrefs.tagsHidden = visible
                } label: {
                    Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(visible ? ListsTokens.accent : Color.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                IconBadge(
                    systemName: "number",
                    hue: ListsTokens.tagAccent,
                    shape: .roundedSquare
                )
                Text("Tags")
                Spacer()
            }
        } footer: {
            Text("Tags pins to the top of My Lists. Uncheck to hide.")
        }
    }
}
