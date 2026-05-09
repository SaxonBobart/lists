import SwiftUI

/// Settings root. Six sections per PRODUCT-SPEC.md Tier 3: Appearance,
/// Sync, Triggers, Notifications, Data, About. Skeleton — wires through
/// to placeholder destinations until each subsystem ships.
struct SettingsView: View {
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ListsSpacing.s5) {
                    appearanceSection
                    syncSection
                    triggersSection
                    notificationsSection
                    dataSection
                    aboutSection
                    Spacer().frame(height: ListsSpacing.s8)
                }
                .padding(.horizontal, ListsSpacing.s4)
                .padding(.top, ListsSpacing.s4)
            }
            .background(ListsTokens.Background.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ListsTokens.accent)
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(for: SettingsDestination.self) { dest in
                placeholder(for: dest)
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        section("Appearance") {
            row(icon: "circle.lefthalf.filled", hue: ListsTokens.Hue.purple,
                label: "Theme", value: "System")
            separator
            row(icon: "rectangle.compress.vertical", hue: ListsTokens.Hue.blue,
                label: "Density", value: "Comfortable")
            separator
            row(icon: "textformat.size", hue: ListsTokens.Hue.amber,
                label: "Dynamic Type", value: "System")
        }
    }

    private var syncSection: some View {
        section("Sync") {
            row(icon: "icloud", hue: ListsTokens.Hue.grey,
                label: "Lists Sync", value: "Not yet available", subtle: true)
            separator
            row(icon: "folder", hue: ListsTokens.Hue.grey,
                label: "Self-managed sync folder", value: "Off", subtle: true)
        }
    }

    private var triggersSection: some View {
        section("Triggers") {
            row(icon: "bolt.fill", hue: ListsTokens.Semantic.danger,
                label: "Urgent Alarm Device", value: "This device", subtle: true)
            separator
            row(icon: "location", hue: ListsTokens.Hue.green,
                label: "Location Reminder Devices", value: "This device", subtle: true)
        }
    }

    private var notificationsSection: some View {
        section("Notifications") {
            navRow(dest: .notificationsPermission, icon: "bell", hue: ListsTokens.Hue.purple,
                   label: "Permission", value: "Request")
            separator
            row(icon: "clock", hue: ListsTokens.Hue.blue,
                label: "Default reminder time", value: "9:00 AM")
        }
    }

    private var dataSection: some View {
        section("Data") {
            navRow(dest: .exportLibrary, icon: "square.and.arrow.up", hue: ListsTokens.accent,
                   label: "Export library", value: "")
            separator
            navRow(dest: .rebuildCache, icon: "arrow.clockwise", hue: ListsTokens.Hue.blue,
                   label: "Rebuild cache", value: "")
            separator
            row(icon: "internaldrive", hue: ListsTokens.Hue.grey,
                label: "Storage", value: "App-private")
        }
    }

    private var aboutSection: some View {
        section("About") {
            row(icon: "app.badge", hue: ListsTokens.accent,
                label: "Version", value: appVersion)
            separator
            row(icon: "doc.plaintext", hue: ListsTokens.Hue.grey,
                label: "License", value: "AGPL-3.0-or-later")
            separator
            row(icon: "person", hue: ListsTokens.Hue.grey,
                label: "Made by", value: "Saxon Bobart")
        }
    }

    // MARK: - Section helpers

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(ListsTokens.Foreground.secondary)
                .padding(.horizontal, ListsSpacing.s2)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(card)
        }
    }

    private func row(icon: String, hue: Color, label: String, value: String, subtle: Bool = false) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, hue: hue)
            Text(label)
                .font(ListsTypography.callout)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Spacer()
            Text(value)
                .font(ListsTypography.callout)
                .foregroundStyle(subtle ? ListsTokens.Foreground.tertiary : ListsTokens.Foreground.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, ListsSpacing.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private func navRow(dest: SettingsDestination, icon: String, hue: Color, label: String, value: String) -> some View {
        NavigationLink(value: dest) {
            HStack(spacing: 12) {
                IconBadge(systemName: icon, hue: hue)
                Text(label)
                    .font(ListsTypography.callout)
                    .foregroundStyle(ListsTokens.Foreground.primary)
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .font(ListsTypography.callout)
                        .foregroundStyle(ListsTokens.Foreground.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ListsTokens.Foreground.quaternary)
            }
            .padding(.horizontal, ListsSpacing.s4)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var separator: some View {
        Divider()
            .background(ListsTokens.Separator.translucent)
            .padding(.leading, 16 + 28 + 12)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    // MARK: - Placeholders

    @ViewBuilder
    private func placeholder(for dest: SettingsDestination) -> some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()
            VStack(spacing: ListsSpacing.s4) {
                Image(systemName: dest.iconName)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
                Text(dest.title)
                    .font(ListsTypography.title3)
                Text(dest.placeholderBody)
                    .font(ListsTypography.subheadline)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ListsSpacing.s7)
            }
            .padding(.top, ListsSpacing.s8)
        }
        .navigationTitle(dest.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Computed

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

enum SettingsDestination: String, Hashable, CaseIterable, Sendable {
    case notificationsPermission
    case exportLibrary
    case rebuildCache

    var title: String {
        switch self {
        case .notificationsPermission: return "Notifications"
        case .exportLibrary:           return "Export Library"
        case .rebuildCache:            return "Rebuild Cache"
        }
    }

    var iconName: String {
        switch self {
        case .notificationsPermission: return "bell"
        case .exportLibrary:           return "square.and.arrow.up"
        case .rebuildCache:            return "arrow.clockwise"
        }
    }

    var placeholderBody: String {
        switch self {
        case .notificationsPermission:
            return "Permission request flow lands when notification scheduling ships."
        case .exportLibrary:
            return "ZIP-and-share-sheet export of your Lists folder. Coming soon."
        case .rebuildCache:
            return "Re-walks Documents/Lists/ and rebuilds the in-memory snapshot. Useful if files were edited in another editor."
        }
    }
}
