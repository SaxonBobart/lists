import SwiftUI

/// 7-row × 53-column heatmap for daily habits (one year of cells, GitHub-style).
/// Each cell colored by completion ratio: empty / partial-1 / partial-2 /
/// partial-3 / full per `ListsTokens.Heatmap`.
struct HabitHeatmap: View {
    let item: Item
    var weeks: Int = 53
    var cellSize: CGFloat = 11
    var cellSpacing: CGFloat = 2

    var body: some View {
        let cells = buildCells()

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                legend
                Spacer()
            }
            // Render as 7 rows × N cols by laying out in a grid that flips
            // weeks horizontally. We build a flat array of (week × day) and
            // show 7 columns per row of the grid (so each grid row = 1 day).
            // Simplest: just show cells in a linear LazyVGrid with 7 rows by
            // feeding "day" as the major axis.
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(cellSize), spacing: cellSpacing), count: 7), spacing: cellSpacing) {
                ForEach(cells, id: \.self) { cell in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: cell))
                        .frame(width: cellSize, height: cellSize)
                }
            }
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
                    .frame(width: cellSize, height: cellSize)
            }
            Text("More")
                .font(ListsTypography.caption2)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
    }

    // MARK: - Cell building

    /// Each cell = (date, completionCount, goal).
    private struct Cell: Hashable {
        let date: Date
        let count: Int
        let goal: Int
    }

    private func buildCells() -> [Cell] {
        let cal = Calendar(identifier: .iso8601)
        let goal = item.goalPerCycle
        let totalCells = weeks * 7
        var cells: [Cell] = []
        cells.reserveCapacity(totalCells)

        // Anchor at today; build backwards 'totalCells' days.
        let startOfToday = cal.startOfDay(for: .now)
        for offset in (0..<totalCells).reversed() {
            guard let date = cal.date(byAdding: .day, value: -offset, to: startOfToday) else { continue }
            let key = HabitCycle.key(for: item.frequency ?? .daily, on: date)
            let count = item.completionLog[key] ?? 0
            cells.append(Cell(date: date, count: count, goal: goal))
        }
        return cells
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
}
