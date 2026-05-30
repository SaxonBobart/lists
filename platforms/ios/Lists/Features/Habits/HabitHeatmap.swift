import SwiftUI

/// Per-cycle contribution grid. The shape follows the habit's cadence so the grid
/// always reads as "one square per cycle", and the whole grid fits the card
/// without scrolling:
///   • **daily**   — the last 30 days, 10 squares per row (3 rows),
///   • **weekly**  — the last 52 weeks, 13 squares per row (4 rows),
///   • **monthly** — the last 12 months, one row of squares labelled J/F/M…
/// Each square is coloured by that cycle's completion ratio (`count / goal`) on the
/// `ListsTokens.Heatmap` scale. Tapping a square reports a representative date in
/// that cycle so the detail screen can log/correct a completion there.
struct HabitHeatmap: View {
    let item: Item
    /// When set, each square becomes tappable and reports a date inside its cycle.
    /// `nil` keeps the grid a read-only visualization for every other caller.
    var onSelectCycle: ((Date) -> Void)? = nil

    private let cellSpacing: CGFloat = 4
    private let legendCell: CGFloat = 11

    private var cadence: HabitFrequency { (item.frequency ?? .daily).normalizedForHabit }

    /// (cycles to draw, columns per row) for the cadence. The product is the exact
    /// cell count so every row is full — 30 = 10×3, 52 = 13×4, 12 = 12×1.
    private var layout: (limit: Int, columns: Int) {
        switch cadence {
        case .weekly:  return (52, 13)
        case .monthly: return (12, 12)
        default:       return (30, 10)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            grid
            legend
        }
    }

    // MARK: - Grid

    /// A non-scrolling grid of square cells that fills the card width. Columns are
    /// flexible so the squares size to the device; the monthly row also carries a
    /// month-initial label under each square.
    private var grid: some View {
        let cells = cycleCells(limit: layout.limit)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: cellSpacing),
            count: layout.columns
        )
        return LazyVGrid(columns: columns, spacing: cellSpacing) {
            ForEach(cells) { cell in
                if cadence == .monthly {
                    VStack(spacing: 3) {
                        cellView(cell)
                        Text(monthInitial(cell.date))
                            .font(.system(size: 9))
                            .foregroundStyle(ListsTokens.Foreground.tertiary)
                    }
                } else {
                    cellView(cell)
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: Cell) -> some View {
        let square = RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color(for: cell))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
        if let onSelectCycle {
            Button { onSelectCycle(cell.date) } label: { square }
                .buttonStyle(.plain)
                .accessibilityLabel(cellAccessibilityLabel(cell.date))
                .accessibilityValue(cell.count == 0 ? "no completions" : "\(cell.count)")
        } else {
            square
        }
    }

    // MARK: - Legend

    private var legend: some View {
        let scale: [Color] = [
            ListsTokens.Heatmap.empty,
            ListsTokens.Heatmap.level1,
            ListsTokens.Heatmap.level2,
            ListsTokens.Heatmap.level3,
            ListsTokens.Heatmap.level4
        ]
        return HStack(spacing: 6) {
            Text("Less")
                .font(ListsTypography.caption2)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
            ForEach(0..<scale.count, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(scale[idx])
                    .frame(width: legendCell, height: legendCell)
            }
            Text("More")
                .font(ListsTypography.caption2)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
    }

    // MARK: - Cell building

    /// Each cell = (representative date, completionCount, goal).
    private struct Cell: Identifiable, Hashable {
        let date: Date
        let count: Int
        let goal: Int
        var id: Date { date }
    }

    /// One cell per cycle (oldest → newest), from `recentCycles`. Daily cycles are
    /// per-day, so the daily grid still reads as real day-by-day activity.
    private func cycleCells(limit: Int) -> [Cell] {
        let goal = item.goalPerCycle
        return HabitStats.recentCycles(for: item, limit: limit).map {
            Cell(date: $0.start, count: $0.count, goal: goal)
        }
    }

    private func color(for cell: Cell) -> Color {
        guard cell.goal > 0, cell.count > 0 else { return ListsTokens.Heatmap.empty }
        let ratio = Double(cell.count) / Double(cell.goal)
        switch ratio {
        case 1...:    return ListsTokens.Heatmap.level4
        case 0.66...: return ListsTokens.Heatmap.level3
        case 0.33...: return ListsTokens.Heatmap.level2
        default:      return ListsTokens.Heatmap.level1
        }
    }

    private func monthInitial(_ date: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let m = cal.component(.month, from: date)
        let symbols = cal.veryShortMonthSymbols
        return (1...12).contains(m) ? symbols[m - 1] : ""
    }

    private func cellAccessibilityLabel(_ date: Date) -> String {
        switch cadence {
        case .monthly: return Self.monthLabel.string(from: date)
        case .weekly:  return "Week of \(Self.dayLabel.string(from: date))"
        default:       return Self.dayLabel.string(from: date)
        }
    }

    private static let dayLabel: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let monthLabel: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}
