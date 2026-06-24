import SwiftUI

/// Edit Lists sheet — manages the sidebar's pinned section: tile
/// visibility + order. Each row has a leading checkbox + drag handle.
/// Uncheck → hides the tile in the sidebar; reordering controls sidebar
/// tile order. Tags is a pinned tile like the rest.
///
/// User-list reordering, deletion, and editing now live on the sidebar
/// itself (direct drag, swipe actions, and long-press context menu) and are
/// no longer surfaced here.
struct EditListsSheet: View {
    let store: ItemStore
    @Bindable var autoListPrefs: AutoListPreferences

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                autoListsSection
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
                    .accessibilityIdentifier("editlists.done")
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
                .accessibilityIdentifier("editlists.pinned.\(smartList.rawValue)")
            }
            .onMove { source, destination in
                autoListPrefs.move(fromOffsets: source, toOffset: destination)
            }
        } header: {
            Text("Pinned Lists")
        } footer: {
            Text("Pinned lists sit at the top of the sidebar. Uncheck to hide, drag to reorder.")
        }
    }
}
