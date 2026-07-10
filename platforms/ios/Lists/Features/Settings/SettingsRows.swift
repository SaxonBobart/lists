import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Section(title) {
            content()
        }
    }
}

struct SettingsRowLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .labelStyle(GlyphLabelStyle())
            .foregroundStyle(.primary)
    }
}

struct SettingsValueRow: View {
    let icon: String
    let label: String
    let value: String
    var subtle = false

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(subtle ? .tertiary : .secondary)
        } label: {
            SettingsRowLabel(title: label, icon: icon)
        }
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabel(title: label, icon: icon)
        }
        .toggleStyle(SwitchToggleStyle(tint: .green))
    }
}

struct SettingsActionValueRow: View {
    let icon: String
    let label: String
    let value: String
    var isAction = false
    let action: () -> Void

    var body: some View {
        if isAction {
            Button(action: action) {
                rowContent
            }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        LabeledContent {
            if isAction {
                Text(value)
                    .foregroundStyle(.tint)
            } else {
                Text(value)
                    .foregroundStyle(.secondary)
            }
        } label: {
            SettingsRowLabel(title: label, icon: icon)
        }
    }
}

struct SettingsDatePickerRow: View {
    let icon: String
    let label: String
    @Binding var selection: Date

    var body: some View {
        DatePicker(selection: $selection, displayedComponents: .hourAndMinute) {
            SettingsRowLabel(title: label, icon: icon)
        }
    }
}

/// Picks the list used by the overview "+" button. List-detail plus buttons
/// still create inside the list currently being viewed.
struct DefaultCaptureListRow: View {
    let lists: [ItemList]
    @Binding var selection: String

    var body: some View {
        Picker(selection: $selection) {
            ForEach(activeLists, id: \.id) { list in
                Text(list.name).tag(list.id)
            }
        } label: {
            SettingsRowLabel(title: "Default List", icon: "scope")
        }
        .pickerStyle(.menu)
        .tint(ListsTokens.Foreground.secondary)
        .accessibilityIdentifier("settings.defaultCaptureList.menu")
        .onAppear {
            if selectedList == nil, let fallback = activeLists.first {
                selection = fallback.id
            }
        }
    }

    private var activeLists: [ItemList] {
        lists
            .filter { $0.deletedAt == nil }
            .sorted { $0.position < $1.position }
    }

    private var selectedList: ItemList? {
        if let selected = activeLists.first(where: { $0.id == selection }) {
            return selected
        }
        if let inbox = activeLists.first(where: { $0.id == ItemList.inboxId }) {
            return inbox
        }
        return activeLists.first
    }
}

struct SettingsNavigationRow<Value: Hashable>: View {
    let destination: Value
    let icon: String
    let label: String
    var value = ""

    var body: some View {
        NavigationLink(value: destination) {
            if value.isEmpty {
                SettingsRowLabel(title: label, icon: icon)
            } else {
                LabeledContent {
                    Text(value)
                        .foregroundStyle(.secondary)
                } label: {
                    SettingsRowLabel(title: label, icon: icon)
                }
            }
        }
    }
}

struct SettingsPluginRow<Value: Hashable>: View {
    let destination: Value
    let icon: String
    let title: String
    let subtitle: String
    let accessibilityId: String
    @Binding var isOn: Bool

    var body: some View {
        NavigationLink(value: destination) {
            LabeledContent {
                Text(isOn ? "On" : "Off")
                    .foregroundStyle(.secondary)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    SettingsRowLabel(title: title, icon: icon)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("\(accessibilityId).details")
    }
}
