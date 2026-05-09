import SwiftUI

/// Liquid-Glass "+" floating button with a custom drag gesture. Ported
/// from the old app (`Design/Components/FloatingAddButton.swift`).
///
/// - Tap → fires `action`.
/// - Press-and-move → starts dragging immediately (no long-press wait).
///   The button visibly follows the finger and the parent receives
///   `onDragChanged` / `onDragEnded` with the touch location in
///   **global** coordinate space. The parent does the hit-testing
///   against drop targets it already collected via PreferenceKey.
struct FloatingAddButton: View {
    var tint: Color = .accentColor
    var accessibilityLabel: String = "New Item"
    /// Movement threshold (in points) before a touch is treated as a drag
    /// rather than a tap.
    var dragThreshold: CGFloat = 5
    let action: () -> Void
    /// Receives touch position in **global** coordinate space.
    var onDragChanged: ((CGPoint) -> Void)? = nil
    /// Receives touch position in **global** coordinate space on release.
    var onDragEnded: ((CGPoint) -> Void)? = nil
    /// Bound to the parent so it can disable list scrolling while the FAB
    /// is being touched. Goes true the moment the finger lands on the
    /// button, false the moment it lifts.
    @Binding var isInteracting: Bool

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    init(
        tint: Color = .accentColor,
        accessibilityLabel: String = "New Item",
        dragThreshold: CGFloat = 5,
        action: @escaping () -> Void,
        onDragChanged: ((CGPoint) -> Void)? = nil,
        onDragEnded: ((CGPoint) -> Void)? = nil,
        isInteracting: Binding<Bool> = .constant(false)
    ) {
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
        self.dragThreshold = dragThreshold
        self.action = action
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self._isInteracting = isInteracting
    }

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 56, height: 56)
            .glassEffect(.regular.interactive(), in: Circle())
            .scaleEffect(isDragging ? 1.12 : 1.0)
            .shadow(color: .black.opacity(isDragging ? 0.30 : 0), radius: 14, x: 0, y: 8)
            .offset(dragOffset)
            .contentShape(Circle())
            .accessibilityLabel(accessibilityLabel)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if !isInteracting { isInteracting = true }
                        let translated = abs(value.translation.width) + abs(value.translation.height)
                        if !isDragging, translated > dragThreshold {
                            withAnimation(.spring(response: 0.20, dampingFraction: 0.75)) {
                                isDragging = true
                            }
                        }
                        if isDragging {
                            dragOffset = value.translation
                            onDragChanged?(value.location)
                        }
                    }
                    .onEnded { value in
                        let translated = abs(value.translation.width) + abs(value.translation.height)
                        let wasTap = translated <= dragThreshold
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.7)) {
                            dragOffset = .zero
                            isDragging = false
                        }
                        isInteracting = false
                        if wasTap {
                            action()
                        } else {
                            onDragEnded?(value.location)
                        }
                    }
            )
    }
}

/// Generic drop-target frame reported via PreferenceKey. Used by Sidebar
/// (each list / smart list row reports its frame) and by ListDetailView
/// (each section header reports its frame). The FAB's drag handlers
/// hit-test against these.
struct DropTargetFrame: Equatable {
    let id: String
    let rect: CGRect
}

struct DropTargetFrameKey: PreferenceKey {
    static let defaultValue: [DropTargetFrame] = []
    static func reduce(value: inout [DropTargetFrame], nextValue: () -> [DropTargetFrame]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Report this view's global frame as a drop target with `id`.
    func dropTarget(_ id: String) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: DropTargetFrameKey.self,
                    value: [DropTargetFrame(id: id, rect: geo.frame(in: .global))]
                )
            }
        )
    }
}
