import SwiftUI
import UIKit

/// Settings root for appearance, built-in plugins, notifications, data, and about.
/// Local maintenance tools open detail screens; unavailable features stay out of app UI.
struct SettingsView: View {
    let store: ItemStore
    @Bindable var autoListPrefs: AutoListPreferences
    private let reminderDefaults: UserDefaults
    private let notificationStatusProvider: () async -> NotificationDeliveryStatus
    private let requestNotificationAuthorization: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var defaultReminderTime: Date
    @State private var notificationStatus: NotificationDeliveryStatus = .notDetermined
    @State private var isRebuildingLibrary = false
    @AppStorage(CorePluginPreferences.habitsEnabledKey) private var habitsPluginEnabled = true

    init(
        store: ItemStore,
        autoListPrefs: AutoListPreferences,
        reminderDefaults: UserDefaults = .standard
    ) {
        self.init(
            store: store,
            autoListPrefs: autoListPrefs,
            reminderDefaults: reminderDefaults,
            notificationStatusProvider: Self.currentNotificationStatus,
            requestNotificationAuthorization: Self.requestNotifications
        )
    }

    init(
        store: ItemStore,
        autoListPrefs: AutoListPreferences,
        reminderDefaults: UserDefaults = .standard,
        notificationStatusProvider: @escaping () async -> NotificationDeliveryStatus,
        requestNotificationAuthorization: @escaping () async -> Bool
    ) {
        self.store = store
        self.autoListPrefs = autoListPrefs
        self.reminderDefaults = reminderDefaults
        self.notificationStatusProvider = notificationStatusProvider
        self.requestNotificationAuthorization = requestNotificationAuthorization
        _defaultReminderTime = State(
            initialValue: ReminderPreferences.defaultTime(defaults: reminderDefaults)
        )
    }

    var body: some View {
        NavigationStack {
            settingsForm {
                listsSection
                pluginsSection
                notificationsSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(isRebuildingLibrary || store.isReloadingFromDisk)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("settings.close")
                }
            }
            .navigationDestination(for: SettingsDestination.self) { dest in
                destination(for: dest)
            }
            .task {
                await refreshNotificationStatus()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshNotificationStatus() }
                }
            }
        }
        .interactiveDismissDisabled(isRebuildingLibrary || store.isReloadingFromDisk)
    }

    private func settingsForm<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Form {
            content()
        }
    }

    // MARK: - Sections

    private var listsSection: some View {
        SettingsSection(title: "Lists") {
            SettingsToggleRow(icon: "number",
                              label: "Show Counts on Pinned Lists",
                              isOn: $autoListPrefs.showTileCounts)
                .accessibilityIdentifier("settings.showTileCounts")
            DefaultNewItemTypeRow(
                selection: $autoListPrefs.defaultNewItemType,
                habitsPluginEnabled: habitsPluginEnabled
            )
                .accessibilityIdentifier("settings.defaultNewItemType")
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
            defaultReminderTimeRow
                .accessibilityIdentifier("settings.defaultReminderTime")
        }
    }

    private var notificationPermissionRow: some View {
        let display = Self.notificationPermissionDisplay(for: notificationStatus)
        return SettingsActionValueRow(
            icon: "bell",
            label: "Permission",
            value: display.text,
            isAction: display.canRequest || display.opensSettings
        ) {
            if display.canRequest {
                Task {
                    _ = await requestNotificationAuthorization()
                    await refreshNotificationStatus()
                }
            } else if display.opensSettings,
                      let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                openURL(url)
            }
        }
        .accessibilityIdentifier("settings.notificationsPermission")
    }

    private var defaultReminderTimeRow: some View {
        SettingsDatePickerRow(
            icon: "clock",
            label: "Default reminder time",
            selection: Binding(
                get: { defaultReminderTime },
                set: { newValue in
                    defaultReminderTime = newValue
                    ReminderPreferences.setDefaultTime(newValue, defaults: reminderDefaults)
                }
            )
        )
        .accessibilityIdentifier("settings.defaultReminderTime.picker")
    }

    private var dataSection: some View {
        SettingsSection(title: "Data") {
            SettingsNavigationRow(destination: SettingsDestination.exportLibrary,
                                  icon: "square.and.arrow.up",
                                  label: "Export library")
                .accessibilityIdentifier("settings.exportLibrary")
            SettingsNavigationRow(destination: SettingsDestination.rebuildCache,
                                  icon: "arrow.clockwise",
                                  label: "Rebuild cache")
                .accessibilityIdentifier("settings.rebuildCache")
            SettingsValueRow(icon: "internaldrive",
                             label: "Storage", value: "App-private")
                .accessibilityIdentifier("settings.storage")
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            SettingsValueRow(icon: "app.badge",
                             label: "Version", value: appVersion)
                .accessibilityIdentifier("settings.version")
            SettingsValueRow(icon: "doc.plaintext",
                             label: "License", value: "AGPL-3.0-or-later")
                .accessibilityIdentifier("settings.license")
            SettingsValueRow(icon: "person",
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
            RebuildLibraryView(store: store, isRebuilding: $isRebuildingLibrary)
        }
    }

    private var pluginsView: some View {
        settingsForm {
            systemPluginsSection
        }
        .navigationTitle("Plugins")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pluginSettingsView(_ plugin: CorePlugin) -> some View {
        settingsForm {
            SettingsSection(title: plugin.displayName) {
                SettingsToggleRow(icon: plugin.settingsIcon,
                                  label: "Enable \(plugin.displayName)",
                                  isOn: binding(for: plugin))
                    .accessibilityIdentifier("settings.plugin.\(plugin.id).enabled")
                SettingsValueRow(icon: "gearshape",
                                 label: "Settings",
                                 value: "None yet",
                                 subtle: true)
                    .accessibilityIdentifier("settings.plugin.\(plugin.id).settings")
            }
        }
        .navigationTitle(plugin.displayName)
        .navigationBarTitleDisplayMode(.inline)
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
        for status: NotificationDeliveryStatus
    ) -> (text: String, canRequest: Bool, opensSettings: Bool) {
        switch status {
        case .notDetermined:
            return ("Request", true, false)
        case .denied:
            return ("Off", false, true)
        case .quiet:
            return ("Quiet", false, true)
        case .summarized:
            return ("Summary", false, true)
        case .enabled:
            return ("On", false, false)
        }
    }

    nonisolated private static func currentNotificationStatus() async -> NotificationDeliveryStatus {
        await NotificationScheduler.shared.deliveryStatus()
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
}
