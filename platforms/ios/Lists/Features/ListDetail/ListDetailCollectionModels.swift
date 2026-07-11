import CoreGraphics
import Foundation

extension ListDetailCollectionView {
    nonisolated static func sectionHeaderShowsTopDivider(
        key: String,
        orderedSectionKeys: [String],
        hasSubLists: Bool
    ) -> Bool {
        hasSubLists || orderedSectionKeys.first != key
    }

    enum SectionKey: Hashable, Sendable {
        case moveDestination
        case subLists
        case section(key: String)
    }

    enum RowItem: Hashable, Sendable {
        case moveNone
        case subListsHeader
        case subListChild(id: String)
        case sectionHeader(key: String)
        /// A section header in inline-rename mode (focused text field).
        /// Distinct identity from `.sectionHeader` so flipping into/out of
        /// editing forces a fresh, auto-focusing cell — mirrors `.editingItem`.
        case editingSectionHeader(key: String)
        case sectionDropPlaceholder(id: String)
        case item(id: UUID, indent: Int)
        /// The single row currently in inline-edit mode. Distinct identity so
        /// live typing never triggers the `.item` content-reload diff (which
        /// would tear down the keyboard), and so swipe/drag/context-menu — all
        /// gated on `.item` — skip it.
        case editingItem(id: UUID, indent: Int)
    }

    /// Everything `makeItemReg` feeds into an `ItemRow` that affects how the
    /// row draws. `applySnapshot` compares this against the previous apply to
    /// reload rows whose visible content changed even though their diffable
    /// identity (`RowItem.item(id:indent:)`) did not.
    struct ItemRenderState: Equatable {
        let item: Item
        let indent: Int
        let isOverdue: Bool
        let inSelectMode: Bool
        let inMoveMode: Bool
        let isSelected: Bool
        let isExpanded: Bool
        /// Drives the trailing collapse chevron — depends on *other* items'
        /// `parentId`, so it isn't covered by `item` equality alone.
        let hasChildren: Bool
    }

    struct SectionHeaderRenderState: Equatable {
        let displayName: String
        let showsTopDivider: Bool
    }

    enum SectionDropTarget: Hashable {
        case before(String)
        case afterLast
    }

    /// Unified drop target model: a drag either lands into a row (force-nest
    /// under it) or in a gap between rows. Vertical position picks the gap;
    /// horizontal position picks the indent at that gap.
    enum ItemDropTarget: Hashable {
        case nestInto(UUID)
        case gap(GapPosition)
    }

    struct GapPosition: Hashable {
        let sectionKey: String
        /// Row this gap sits above in the section's flat-with-children order.
        /// `nil` means "end of section".
        let beforeRowId: UUID?
        /// Chosen depth at this gap, from touch.x. 0 = top-level, capped at
        /// `ListsNesting.maxDisplayDepth`.
        let indent: Int
    }

    struct VisibleRow {
        let id: UUID
        let depth: Int
        var frame: CGRect
    }

    enum ItemDropCueStyle: Equatable {
        case placement
        case nesting
    }
}
