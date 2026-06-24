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
