import SwiftUI

struct HabitOverviewContent: View {
    let item: Item
    let store: ItemStore
    let onAddCompletion: (Date) -> Void
    let onEditCompletion: (HabitCompletion) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListsSpacing.s4) {
                Text(item.title)
                    .font(ListsTypography.largeTitle.bold())
                    .foregroundStyle(ListsTokens.Foreground.primary)

                HStack(alignment: .top, spacing: ListsSpacing.s4) {
                    streakCard
                    thisCycleCard
                }

                gridCard
                recentCard
                Spacer().frame(height: ListsSpacing.s8)
            }
            .padding(.horizontal, ListsSpacing.s4)
            .padding(.top, ListsSpacing.s4)
        }
        .background(ListsTokens.Background.grouped)
    }

    @ViewBuilder
    private var streakCard: some View {
        if item.showStreak {
            statCard(
                icon: "flame.fill",
                iconTint: .orange,
                value: "\(streak)",
                caption: streakCaption,
                a11yLabel: "Streak",
                a11yValue: "\(streak) \(streakCaption)"
            )
        } else {
            let total = HabitStats.totalCompletions(for: item)
            statCard(
                icon: "checkmark.circle.fill",
                iconTint: ListsTokens.accent,
                value: "\(total)",
                caption: "completions",
                a11yLabel: "Total completions",
                a11yValue: "\(total)"
            )
        }
    }

    private var thisCycleCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s2) {
            Image(systemName: "target")
                .font(.headline)
                .foregroundStyle(ListsTokens.accent)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(currentCount)")
                    .font(ListsTypography.largeTitle)
                    .foregroundStyle(ListsTokens.Foreground.primary)
                Text("of \(item.goalPerCycle)")
                    .font(ListsTypography.footnote)
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cycleCaption)
            .accessibilityValue("\(currentCount) of \(item.goalPerCycle)")

            Text(cycleCaption)
                .font(ListsTypography.footnote)
                .foregroundStyle(ListsTokens.Foreground.secondary)

            HStack(spacing: ListsSpacing.s2) {
                stepperButton(
                    system: "minus",
                    enabled: currentCount > 0,
                    a11y: "Remove one",
                    id: "habit.decrement"
                ) {
                    Task { try? await store.removeLatestCompletion(in: .now, for: item.id) }
                }
                stepperButton(
                    system: "plus",
                    enabled: currentCount < item.goalPerCycle,
                    a11y: "Add one",
                    id: "habit.increment"
                ) {
                    Task { try? await store.incrementHabit(item.id) }
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ListsSpacing.s4)
        .background(card)
    }

    private func statCard(
        icon: String,
        iconTint: Color,
        value: String,
        caption: String,
        a11yLabel: String,
        a11yValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s2) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(iconTint)
            Text(value)
                .font(ListsTypography.largeTitle)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Text(caption)
                .font(ListsTypography.footnote)
                .foregroundStyle(ListsTokens.Foreground.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(ListsSpacing.s4)
        .background(card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityValue(a11yValue)
    }

    private func stepperButton(
        system: String,
        enabled: Bool,
        a11y: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? ListsTokens.accent : ListsTokens.Foreground.tertiary)
                .frame(width: 40, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: ListsRadius.md, style: .continuous)
                        .stroke(enabled ? ListsTokens.accent : ListsTokens.Foreground.tertiary, lineWidth: 1.5)
                )
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
        .accessibilityIdentifier(id)
    }

    private var gridCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            Text(gridTitle)
                .font(ListsTypography.footnote.weight(.semibold))
                .foregroundStyle(ListsTokens.Foreground.secondary)

            HabitHeatmap(item: item, onSelectCycle: { date in
                onAddCompletion(noon(of: date))
            })

            Text("Tap a square to log it")
                .font(ListsTypography.caption2)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            HStack {
                Text("Recent")
                    .font(ListsTypography.footnote.weight(.semibold))
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                Spacer()
                if !item.completions.isEmpty {
                    NavigationLink {
                        HabitCompletionLogView(
                            habitId: item.id,
                            store: store,
                            onAddCompletion: { onAddCompletion(.now) },
                            onEditCompletion: onEditCompletion
                        )
                    } label: {
                        Text("See All").font(ListsTypography.footnote)
                    }
                    .accessibilityIdentifier("habit.seeAll")
                }
            }

            if recentEntries.isEmpty {
                Text("No completions logged yet.")
                    .font(ListsTypography.footnote)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .padding(.vertical, 2)
            } else {
                ForEach(recentEntries) { entry in
                    Button { onEditCompletion(entry) } label: { recentRow(entry) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("habit.recent.entry")
                    if entry.id != recentEntries.last?.id {
                        Divider()
                    }
                }
            }

            Button { onAddCompletion(.now) } label: {
                Label("Add Completion", systemImage: "plus")
            }
            .accessibilityIdentifier("habit.addCompletion")
            .padding(.top, 2)
        }
        .padding(ListsSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private func recentRow(_ entry: HabitCompletion) -> some View {
        HStack(spacing: ListsSpacing.s3) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ListsTokens.accent)
            Text(Self.entryDateFormatter.string(from: entry.at))
                .foregroundStyle(ListsTokens.Foreground.primary)
            Spacer()
            Text(Self.timeFormatter.string(from: entry.at))
                .font(ListsTypography.footnote)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    private var cadence: HabitFrequency { (item.frequency ?? .daily).normalizedForHabit }

    private var currentCount: Int {
        let key = HabitCycle.key(for: cadence, on: .now)
        return item.completions.filter { HabitCycle.key(for: cadence, on: $0.at) == key }.count
    }

    private var streak: Int { HabitStats.streak(for: item) }

    private var streakCaption: String {
        switch cadence {
        case .weekly:  return "week streak"
        case .monthly: return "month streak"
        default:       return "day streak"
        }
    }

    private var cycleCaption: String {
        let noun = HabitStats.cycleNoun(for: cadence)
        return noun.prefix(1).uppercased() + noun.dropFirst()
    }

    private var gridTitle: String {
        switch cadence {
        case .weekly:  return "Last 52 Weeks"
        case .monthly: return "Last 12 Months"
        default:       return "Last 30 Days"
        }
    }

    private var recentEntries: [HabitCompletion] {
        Array(item.completions.sorted { $0.at > $1.at }.prefix(5))
    }

    private func noon(of date: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let entryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}
