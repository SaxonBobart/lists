import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ListsTypography.subheadline.weight(.semibold))
                .foregroundStyle(ListsTokens.Foreground.secondary)
                .padding(.horizontal, ListsSpacing.s2)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
                    .fill(ListsTokens.Background.elevated)
            )
        }
    }
}

struct SettingsValueRow: View {
    let icon: String
    let hue: Color
    let label: String
    let value: String
    var subtle = false

    var body: some View {
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
        .settingsRowFrame()
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let hue: Color
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, hue: hue)
            Toggle(isOn: $isOn) {
                Text(label)
                    .font(ListsTypography.callout)
                    .foregroundStyle(ListsTokens.Foreground.primary)
            }
            .tint(ListsTokens.accent)
        }
        .settingsRowFrame()
    }
}

/// Picks the list used by the overview "+" button. List-detail plus buttons
/// still create inside the list currently being viewed.
struct DefaultCaptureListRow: View {
    let lists: [ItemList]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "scope", hue: selectedHue)
            Text("Default List")
                .font(ListsTypography.callout)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Spacer()
            Menu {
                Picker("Default List", selection: $selection) {
                    ForEach(activeLists, id: \.id) { list in
                        Label(list.name, systemImage: list.icon).tag(list.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedName)
                        .font(ListsTypography.callout)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ListsTokens.Foreground.quaternary)
                }
            }
            .accessibilityIdentifier("settings.defaultCaptureList.menu")
        }
        .settingsRowFrame()
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

    private var selectedName: String {
        selectedList?.name ?? "None"
    }

    private var selectedHue: Color {
        selectedList.map { ListsTokens.listColor($0.color) } ?? ListsTokens.Hue.grey
    }
}

struct SettingsNavigationRow<Value: Hashable>: View {
    let destination: Value
    let icon: String
    let hue: Color
    let label: String
    var value = ""

    var body: some View {
        NavigationLink(value: destination) {
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
            .settingsRowFrame()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsPluginRow<Value: Hashable>: View {
    let destination: Value
    let icon: String
    let hue: Color
    let title: String
    let subtitle: String
    let accessibilityId: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: destination) {
                HStack(spacing: 12) {
                    IconBadge(systemName: icon, hue: hue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(ListsTypography.callout)
                            .foregroundStyle(ListsTokens.Foreground.primary)
                        Text(subtitle)
                            .font(ListsTypography.footnote)
                            .foregroundStyle(ListsTokens.Foreground.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ListsTokens.Foreground.quaternary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(accessibilityId).details")

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(ListsTokens.accent)
                .accessibilityIdentifier("\(accessibilityId).enabled")
        }
        .settingsRowFrame()
    }
}

struct SettingsSeparator: View {
    var body: some View {
        Divider()
            .background(ListsTokens.Separator.translucent)
            .padding(.leading, 16 + 28 + 12)
    }
}

extension View {
    func settingsRowFrame() -> some View {
        padding(.horizontal, ListsSpacing.s4)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
    }
}
