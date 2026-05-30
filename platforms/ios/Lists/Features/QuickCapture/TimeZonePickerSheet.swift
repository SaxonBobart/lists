import SwiftUI

/// Searchable IANA Time Zone picker. The "Device" row at the top maps to a
/// `nil` selection — the item falls back to whatever the device thinks the
/// current TZ is. Each row shows the city name (last identifier segment with
/// underscores replaced) and a small UTC-offset label.
struct TimeZonePickerSheet: View {
    @Binding var identifier: String?

    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        identifier = nil
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Device")
                                    .foregroundStyle(.primary)
                                Text(TimeZone.current.identifier.replacingOccurrences(of: "_", with: " "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if identifier == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                ForEach(filteredGroups, id: \.region) { group in
                    Section(group.region) {
                        ForEach(group.zones, id: \.self) { zone in
                            Button {
                                identifier = zone
                                dismiss()
                            } label: {
                                HStack {
                                    Text(cityName(for: zone))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(offsetLabel(for: zone))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    if identifier == zone {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                            .padding(.leading, 6)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Time Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel")
                    }
                    .tint(.primary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Data

    private struct ZoneGroup: Hashable {
        let region: String
        let zones: [String]
    }

    private var groups: [ZoneGroup] {
        let identifiers = TimeZone.knownTimeZoneIdentifiers.sorted()
        let byRegion = Dictionary(grouping: identifiers) { id -> String in
            id.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "Other"
        }
        return byRegion
            .sorted(by: { $0.key < $1.key })
            .map { ZoneGroup(region: $0.key, zones: $0.value) }
    }

    private var filteredGroups: [ZoneGroup] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return groups }
        return groups
            .map { group in
                ZoneGroup(
                    region: group.region,
                    zones: group.zones.filter { zone in
                        cityName(for: zone).lowercased().contains(trimmed)
                            || zone.lowercased().contains(trimmed)
                    }
                )
            }
            .filter { !$0.zones.isEmpty }
    }

    private func cityName(for identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    private func offsetLabel(for identifier: String) -> String {
        guard let tz = TimeZone(identifier: identifier) else { return "" }
        let seconds = tz.secondsFromGMT()
        let hours = seconds / 3600
        let minutes = abs(seconds % 3600) / 60
        let sign = hours >= 0 ? "+" : "-"
        if minutes == 0 {
            return "GMT\(sign)\(abs(hours))"
        } else {
            return String(format: "GMT%@%d:%02d", sign, abs(hours), minutes)
        }
    }
}

/// Display label for the Time Zone row.
enum TimeZoneLabel {
    static func display(for identifier: String?) -> String {
        let id = identifier ?? TimeZone.current.identifier
        let last = id.split(separator: "/").last.map(String.init) ?? id
        return last.replacingOccurrences(of: "_", with: " ")
    }
}
