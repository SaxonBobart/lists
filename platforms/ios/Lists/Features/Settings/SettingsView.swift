import SwiftUI
import UserNotifications

/// Settings root for appearance, built-in plugins, notifications, data, and about.
/// Local maintenance tools open detail screens; unavailable features stay out of app UI.
struct SettingsView: View {
    let store: ItemStore
    @Bindable var autoListPrefs: AutoListPreferences
    private let notificationStatusProvider: () async -> UNAuthorizationStatus
    private let requestNotificationAuthorization: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var defaultReminderTime = ReminderPreferences.defaultTime()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @AppStorage(CorePluginPreferences.habitsEnabledKey) private var habitsPluginEnabled = true

    init(store: ItemStore, autoListPrefs: AutoListPreferences) {
        self.init(
            store: store,
            autoListPrefs: autoListPrefs,
            notificationStatusProvider: Self.currentNotificationStatus,
            requestNotificationAuthorization: Self.requestNotifications
        )
    }

    init(
        store: ItemStore,
        autoListPrefs: AutoListPreferences,
        notificationStatusProvider: @escaping () async -> UNAuthorizationStatus,
        requestNotificationAuthorization: @escaping () async -> Bool
    ) {
        self.store = store
        self.autoListPrefs = autoListPrefs
        self.notificationStatusProvider = notificationStatusProvider
        self.requestNotificationAuthorization = requestNotificationAuthorization
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ListsSpacing.s5) {
                    listsSection
                    pluginsSection
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
                    // Solid blue circle + white ✓ — same prominent style as the
                    // inline editor's done tick (`inlineDoneTick`).
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .accessibilityLabel("Done")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(ListsTokens.accent)
                    .accessibilityIdentifier("settings.close")
                }
            }
            .navigationDestination(for: SettingsDestination.self) { dest in
                destination(for: dest)
            }
            .task {
                await refreshNotificationStatus()
            }
        }
    }

    // MARK: - Sections

    private var listsSection: some View {
        SettingsSection(title: "Lists") {
            SettingsToggleRow(icon: "number", hue: ListsTokens.Hue.blue,
                              label: "Show Counts on Pinned Lists",
                              isOn: $autoListPrefs.showTileCounts)
                .accessibilityIdentifier("settings.showTileCounts")
            SettingsSeparator()
            DefaultNewItemTypeRow(
                selection: $autoListPrefs.defaultNewItemType,
                habitsPluginEnabled: habitsPluginEnabled
            )
                .accessibilityIdentifier("settings.defaultNewItemType")
            SettingsSeparator()
            DefaultCaptureListRow(
                lists: store.lists,
                selection: $autoListPrefs.defaultCaptureListId
            )
            .accessibilityIdentifier("settings.defaultCaptureList")
        }
    }

    private var pluginsSection: some View {
        SettingsSection(title: "Plugins") {
            SettingsNavigationRow(destination: SettingsDestination.plugins,
                                  icon: "puzzlepiece.extension",
                                  hue: ListsTokens.Hue.purple,
                                  label: "Core Plugins",
                                  value: "\(enabledPluginCount) enabled")
                .accessibilityIdentifier("settings.plugins.core")
        }
    }

    private var systemPluginsSection: some View {
        SettingsSection(title: "Core Plugins") {
            ForEach(CorePlugin.allCases) { plugin in
                SettingsPluginRow(
                    destination: SettingsDestination.plugin(plugin),
                    icon: plugin.settingsIcon,
                    hue: plugin.settingsHue,
                    title: plugin.displayName,
                    subtitle: plugin.settingsSummary,
                    accessibilityId: "settings.plugin.\(plugin.id)",
                    isOn: binding(for: plugin)
                )
            }
        }
    }

    private var notificationsSection: some View {
        SettingsSection(title: "Notifications") {
            notificationPermissionRow
            SettingsSeparator()
            defaultReminderTimeRow
                .accessibilityIdentifier("settings.defaultReminderTime")
        }
    }

    private var notificationPermissionRow: some View {
        let display = Self.notificationPermissionDisplay(for: notificationStatus)
        return HStack(spacing: 12) {
            IconBadge(systemName: "bell", hue: ListsTokens.Hue.purple)
            Text("Permission")
                .font(ListsTypography.callout)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Spacer()
            if display.canRequest {
                Button(display.text) {
                    Task {
                        _ = await requestNotificationAuthorization()
                        await refreshNotificationStatus()
                    }
                }
                .font(ListsTypography.callout.weight(.semibold))
                .foregroundStyle(ListsTokens.accent)
                .accessibilityIdentifier("settings.notificationsPermission.request")
            } else {
                Text(display.text)
                    .font(ListsTypography.callout)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .accessibilityIdentifier("settings.notificationsPermission.status")
            }
        }
        .settingsRowFrame()
        .accessibilityIdentifier("settings.notificationsPermission")
    }

    private var defaultReminderTimeRow: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "clock", hue: ListsTokens.Hue.blue)
            Text("Default reminder time")
                .font(ListsTypography.callout)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Spacer()
            DatePicker(
                "Default reminder time",
                selection: Binding(
                    get: { defaultReminderTime },
                    set: { newValue in
                        defaultReminderTime = newValue
                        ReminderPreferences.setDefaultTime(newValue)
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .accessibilityIdentifier("settings.defaultReminderTime.picker")
        }
        .settingsRowFrame()
    }

    private var dataSection: some View {
        SettingsSection(title: "Data") {
            SettingsNavigationRow(destination: SettingsDestination.exportLibrary,
                                  icon: "square.and.arrow.up", hue: ListsTokens.accent,
                                  label: "Export library")
                .accessibilityIdentifier("settings.exportLibrary")
            SettingsSeparator()
            SettingsNavigationRow(destination: SettingsDestination.rebuildCache,
                                  icon: "arrow.clockwise", hue: ListsTokens.Hue.blue,
                                  label: "Rebuild cache")
                .accessibilityIdentifier("settings.rebuildCache")
            SettingsSeparator()
            SettingsValueRow(icon: "internaldrive", hue: ListsTokens.Hue.grey,
                             label: "Storage", value: "App-private")
                .accessibilityIdentifier("settings.storage")
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            SettingsValueRow(icon: "app.badge", hue: ListsTokens.accent,
                             label: "Version", value: appVersion)
                .accessibilityIdentifier("settings.version")
            SettingsSeparator()
            SettingsValueRow(icon: "doc.plaintext", hue: ListsTokens.Hue.grey,
                             label: "License", value: "AGPL-3.0-or-later")
                .accessibilityIdentifier("settings.license")
            SettingsSeparator()
            SettingsValueRow(icon: "person", hue: ListsTokens.Hue.grey,
                             label: "Made by", value: "Saxon Bobart")
                .accessibilityIdentifier("settings.madeBy")
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for dest: SettingsDestination) -> some View {
        switch dest {
        case .plugins:
            pluginsView
        case .plugin(let plugin):
            pluginSettingsView(plugin)
        case .exportLibrary:
            ExportLibraryView(store: store)
        case .rebuildCache:
            RebuildLibraryView(store: store)
        }
    }

    private var pluginsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListsSpacing.s5) {
                systemPluginsSection
            }
            .padding(.horizontal, ListsSpacing.s4)
            .padding(.top, ListsSpacing.s4)
        }
        .background(ListsTokens.Background.grouped)
        .navigationTitle("Plugins")
        .navigationBarTitleDisplayMode(.large)
    }

    private func pluginSettingsView(_ plugin: CorePlugin) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListsSpacing.s5) {
                SettingsSection(title: plugin.displayName) {
                    SettingsToggleRow(icon: plugin.settingsIcon,
                                      hue: plugin.settingsHue,
                                      label: "Enable \(plugin.displayName)",
                                      isOn: binding(for: plugin))
                        .accessibilityIdentifier("settings.plugin.\(plugin.id).enabled")
                    SettingsSeparator()
                    SettingsValueRow(icon: "gearshape",
                                     hue: ListsTokens.Hue.grey,
                                     label: "Settings",
                                     value: "None yet",
                                     subtle: true)
                        .accessibilityIdentifier("settings.plugin.\(plugin.id).settings")
                }
            }
            .padding(.horizontal, ListsSpacing.s4)
            .padding(.top, ListsSpacing.s4)
        }
        .background(ListsTokens.Background.grouped)
        .navigationTitle(plugin.displayName)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Computed

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var enabledPluginCount: Int {
        CorePlugin.allCases.filter { plugin in
            switch plugin {
            case .habits:
                return habitsPluginEnabled
            }
        }.count
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await notificationStatusProvider()
    }

    private func binding(for plugin: CorePlugin) -> Binding<Bool> {
        switch plugin {
        case .habits:
            return Binding(
                get: { habitsPluginEnabled },
                set: { enabled in
                    habitsPluginEnabled = enabled
                    let policy = ItemTypePolicy(habitsEnabled: enabled)
                    autoListPrefs.defaultNewItemType = policy.effectiveDefaultType(
                        autoListPrefs.defaultNewItemType
                    )
                }
            )
        }
    }

    nonisolated static func notificationPermissionDisplay(
        for status: UNAuthorizationStatus
    ) -> (text: String, canRequest: Bool) {
        switch status {
        case .notDetermined:
            return ("Request", true)
        case .authorized:
            return ("On", false)
        case .provisional:
            return ("Provisional", false)
        case .ephemeral:
            return ("Temporary", false)
        case .denied:
            return ("Denied", false)
        @unknown default:
            return ("Unknown", false)
        }
    }

    nonisolated private static func currentNotificationStatus() async -> UNAuthorizationStatus {
        await NotificationScheduler.shared.authorizationStatus()
    }

    nonisolated private static func requestNotifications() async -> Bool {
        await NotificationScheduler.shared.requestAuthorizationIfNeeded()
    }
}

enum SettingsDestination: Hashable, Sendable {
    case plugins
    case plugin(CorePlugin)
    case exportLibrary
    case rebuildCache
}

private extension CorePlugin {
    var settingsIcon: String {
        switch self {
        case .habits: return "repeat"
        }
    }

    var settingsHue: Color {
        switch self {
        case .habits: return ListsTokens.Hue.green
        }
    }
}
