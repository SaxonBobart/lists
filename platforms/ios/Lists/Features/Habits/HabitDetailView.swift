import SwiftUI

/// Detail screen for a habit. Shows current cycle count + goal, streak,
/// 12-month heatmap, +1 button. Edit-history is a placeholder for now.
struct HabitDetailView: View {
    let item: Item
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ListsSpacing.s4) {
                    headerCard
                    progressCard
                    heatmapCard
                    Spacer().frame(height: ListsSpacing.s8)
                }
                .padding(.horizontal, ListsSpacing.s4)
                .padding(.top, ListsSpacing.s4)
            }
            .background(ListsTokens.Background.grouped)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Habit")
                        .font(ListsTypography.headline)
                        .foregroundStyle(ListsTokens.Foreground.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ListsTokens.accent)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s2) {
            Text(item.title)
                .font(ListsTypography.title2)
                .foregroundStyle(ListsTokens.Foreground.primary)
            HStack(spacing: ListsSpacing.s4) {
                stat(label: "Frequency", value: frequencyText)
                stat(label: "Goal", value: "\(item.goalPerCycle)")
                if item.showStreak {
                    stat(label: "Streak", value: "\(streak)")
                }
            }
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    // MARK: - Progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            Text("This cycle")
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(ListsTokens.Foreground.secondary)

            HStack(spacing: ListsSpacing.s4) {
                ZStack {
                    Circle()
                        .stroke(ListsTokens.Heatmap.empty, lineWidth: 8)
                        .frame(width: 78, height: 78)
                    Circle()
                        .trim(from: 0, to: cycleProgress)
                        .stroke(ListsTokens.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 78, height: 78)
                    VStack(spacing: 0) {
                        Text("\(currentCount)")
                            .font(ListsTypography.title2)
                            .foregroundStyle(ListsTokens.Foreground.primary)
                        Text("of \(item.goalPerCycle)")
                            .font(ListsTypography.caption1)
                            .foregroundStyle(ListsTokens.Foreground.tertiary)
                    }
                }

                Spacer()

                Button {
                    Task { try? await store.incrementHabit(item.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("+1")
                            .font(ListsTypography.headline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, ListsSpacing.s4)
                    .padding(.vertical, ListsSpacing.s3)
                    .background(
                        RoundedRectangle(cornerRadius: ListsRadius.lg, style: .continuous)
                            .fill(currentCount >= item.goalPerCycle
                                  ? ListsTokens.Foreground.tertiary
                                  : ListsTokens.accent)
                    )
                }
                .disabled(currentCount >= item.goalPerCycle)
                .buttonStyle(.plain)
            }
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    // MARK: - Heatmap

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            Text("Last 12 months")
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(ListsTokens.Foreground.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HabitHeatmap(item: item)
            }
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    // MARK: - Helpers

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(ListsTypography.title3)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Text(label)
                .font(ListsTypography.caption1)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    private var currentCount: Int {
        let key = HabitCycle.key(for: item.frequency ?? .daily, on: .now)
        return item.completionLog[key] ?? 0
    }

    private var cycleProgress: Double {
        guard item.goalPerCycle > 0 else { return 0 }
        return min(1.0, Double(currentCount) / Double(item.goalPerCycle))
    }

    private var streak: Int { HabitStats.streak(for: item) }

    private var frequencyText: String {
        switch item.frequency ?? .daily {
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        case .weekly: return "Weekly"
        case .fortnightly: return "Every 2 weeks"
        case .monthly: return "Monthly"
        case .everyThreeMonths: return "Every 3 months"
        case .everySixMonths: return "Every 6 months"
        case .yearly: return "Yearly"
        case .custom: return "Custom"
        }
    }
}
