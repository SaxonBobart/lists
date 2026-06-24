import SwiftUI

/// Three rows of horizontally-scrolling chips. Tags are distributed
/// column-major (chip N -> row N % 3) so the leftmost columns stay dense.
struct TagChipCloud: View {
    let tags: [String]
    let isAllSelected: Bool
    let isSelected: (String) -> Bool
    let counts: (String) -> Int
    let onAllTap: () -> Void
    let onTap: (String) -> Void
    let allowsEditing: Bool
    let onRename: (String) -> Void
    let onDelete: (String) -> Void

    private let rowCount = 3
    private let spacing: CGFloat = 8

    private var rows: [[String]] {
        var out: [[String]] = Array(repeating: [], count: rowCount)
        for (i, tag) in tags.enumerated() {
            out[i % rowCount].append(tag)
        }
        return out
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(0..<rowCount, id: \.self) { rowIndex in
                    HStack(spacing: spacing) {
                        if rowIndex == 0 {
                            AllTagsChip(isSelected: isAllSelected, onTap: onAllTap)
                        }
                        ForEach(rows[rowIndex], id: \.self) { tag in
                            TagFilterChip(
                                text: tag,
                                count: counts(tag),
                                isSelected: isSelected(tag),
                                onTap: { onTap(tag) },
                                allowsEditing: allowsEditing,
                                onRename: { onRename(tag) },
                                onDelete: { onDelete(tag) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}
