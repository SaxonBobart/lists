import SwiftUI

struct DetailFormRowLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let subtitle: String?
    let systemImage: String
    let iconColor: Color?

    init(title: String, subtitle: String? = nil, systemImage: String, iconColor: Color? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconColor = iconColor
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(iconColor ?? ListsTokens.Foreground.secondary)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .top))
                        )
                }
            }
        }
    }
}

struct DetailFormPickerRowLabel: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
                .font(.footnote)
        }
    }
}

struct DetailFormDisclosureRowLabel: View {
    let title: String
    let value: String?
    let systemImage: String

    init(title: String, value: String? = nil, systemImage: String) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if let value, !value.isEmpty {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
                .font(.footnote)
        }
    }
}

struct DetailFormListMenuRow: View {
    let lists: [ItemList]
    let selectedListId: String
    let selectedList: ItemList?
    let onSelect: (ItemList) -> Void

    var body: some View {
        Menu {
            ForEach(lists, id: \.id) { list in
                Button {
                    onSelect(list)
                } label: {
                    if list.id == selectedListId {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        Label(list.name, systemImage: list.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let list = selectedList {
                    IconBadge(
                        systemName: list.icon,
                        hue: ListsTokens.listColor(list.color),
                        size: 24,
                        glyphSize: 12,
                        shape: .circle
                    )
                } else {
                    Image(systemName: "tray.fill")
                        .imageScale(.small)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                }
                Text("List")
                    .foregroundStyle(.primary)
                Spacer()
                Text(selectedList?.name ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .font(.footnote)
            }
        }
        .buttonStyle(.plain)
        .tint(.primary)
    }
}

struct DetailFormSplitToggleRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    @Binding var isOn: Bool
    let tapTarget: (() -> Void)?
    let verticalPadding: CGFloat

    init(
        title: String,
        subtitle: String?,
        systemImage: String,
        isOn: Binding<Bool>,
        tapTarget: (() -> Void)? = nil,
        verticalPadding: CGFloat = 0
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        _isOn = isOn
        self.tapTarget = tapTarget
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        HStack(spacing: 0) {
            if let tapTarget {
                Button(action: tapTarget) {
                    DetailFormRowLabel(title: title, subtitle: subtitle, systemImage: systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
            } else {
                DetailFormRowLabel(title: title, subtitle: subtitle, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.green)
        }
        .padding(.vertical, verticalPadding)
    }
}
