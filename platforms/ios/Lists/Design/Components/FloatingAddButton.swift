import SwiftUI
import UIKit

/// Liquid-Glass "+" floating button with custom tap, hold, and drag behavior.
///
/// - Tap → fires `action`.
/// - Press-and-hold (no movement) → fires `onLongPress` after a short
///   delay, with a light haptic. Used to open the full capture sheet.
/// - Press-and-move → starts dragging immediately (no long-press wait).
///   The button visibly follows the finger and the parent receives
///   `onDragChanged` / `onDragEnded` with the touch location in
///   **global** coordinate space. The parent does the hit-testing
///   against drop targets it already collected via PreferenceKey.
struct FloatingAddButton: View {
    /// Optional tint applied to both the Liquid Glass material and the glyph.
    /// `nil` = neutral glass with `.primary` glyph (default for the sidebar
    /// home where no list is being viewed).
    var tint: Color?
    /// Optional glyph color override. When `nil`, the glyph uses `.primary`
    /// for the neutral-glass case and `.white` for tinted glass.
    var glyphColor: Color?
    var accessibilityLabel: String = "New Item"
    var size: CGFloat = 56
    /// Movement threshold (in points) before a touch is treated as a drag
    /// rather than a tap.
    var dragThreshold: CGFloat = 5
    /// How long the finger must stay still before a press becomes a long
    /// press rather than a tap.
    var longPressDuration: Double = 0.45
    let action: () -> Void
    /// Receives touch position in **global** coordinate space.
    var onDragChanged: ((CGPoint) -> Void)? = nil
    /// Receives touch position in **global** coordinate space on release.
    var onDragEnded: ((CGPoint) -> Void)? = nil
    /// Fires when the finger is held still past `longPressDuration`.
    var onLongPress: (() -> Void)? = nil
    /// Bound to the parent so it can disable list scrolling while the FAB
    /// is being touched. Goes true the moment the finger lands on the
    /// button, false the moment it lifts.
    @Binding var isInteracting: Bool

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var touchDown: Bool = false
    @State private var longPressFired: Bool = false
    @State private var longPressTask: Task<Void, Never>?

    private var glassStyle: Glass {
        if let tint {
            return .regular.tint(tint).interactive()
        } else {
            return .regular.interactive()
        }
    }

    init(
        tint: Color? = nil,
        glyphColor: Color? = nil,
        accessibilityLabel: String = "New Item",
        size: CGFloat = 56,
        dragThreshold: CGFloat = 5,
        longPressDuration: Double = 0.45,
        action: @escaping () -> Void,
        onDragChanged: ((CGPoint) -> Void)? = nil,
        onDragEnded: ((CGPoint) -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        isInteracting: Binding<Bool> = .constant(false)
    ) {
        self.tint = tint
        self.glyphColor = glyphColor
        self.accessibilityLabel = accessibilityLabel
        self.size = size
        self.dragThreshold = dragThreshold
        self.longPressDuration = longPressDuration
        self.action = action
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onLongPress = onLongPress
        self._isInteracting = isInteracting
    }

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(glyphColor ?? (tint == nil ? Color.primary : Color.white))
            .frame(width: size, height: size)
            .glassEffect(glassStyle, in: Circle())
            .scaleEffect(isDragging ? 1.12 : 1.0)
            .shadow(color: .black.opacity(isDragging ? 0.30 : 0), radius: 14, x: 0, y: 8)
            .offset(dragOffset)
            .contentShape(Circle())
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("floating.add")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .animation(.easeOut(duration: 0.18), value: tint)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if !isInteracting { isInteracting = true }
                        // First touch of this gesture: arm the long-press timer.
                        if !touchDown {
                            touchDown = true
                            armLongPress()
                        }
                        let translated = abs(value.translation.width) + abs(value.translation.height)
                        if !isDragging, translated > dragThreshold {
                            // Movement → it's a drag, not a long press.
                            cancelLongPress()
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
                        cancelLongPress()
                        touchDown = false
                        let translated = abs(value.translation.width) + abs(value.translation.height)
                        let wasTap = translated <= dragThreshold
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.7)) {
                            dragOffset = .zero
                            isDragging = false
                        }
                        isInteracting = false
                        // The long press already fired mid-gesture; the lift
                        // shouldn't also create a tap/drag item.
                        if longPressFired {
                            longPressFired = false
                            return
                        }
                        if wasTap {
                            action()
                        } else {
                            onDragEnded?(value.location)
                        }
                    }
            )
    }

    /// Starts the hold timer. If the finger is still down and hasn't begun
    /// dragging when it elapses, fire `onLongPress` (with a light haptic).
    private func armLongPress() {
        guard onLongPress != nil else { return }
        longPressFired = false
        longPressTask?.cancel()
        longPressTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(longPressDuration))
            guard !Task.isCancelled, touchDown, !isDragging else { return }
            longPressFired = true
            isInteracting = false
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress?()
        }
    }

    private func cancelLongPress() {
        longPressTask?.cancel()
        longPressTask = nil
    }
}
