import SwiftUI
import UIKit

/// A shared touch surface keeps tap, hold, and selected-item drag arbitration
/// independent of SwiftUI's nested scroll and gesture wrappers.
struct CalendarTimelineInteraction: UIViewRepresentable {
    let editable: Bool
    let selected: Bool
    let onTap: () -> Void
    let onSelect: () -> Void
    let onPreview: (CGFloat) -> Void
    let onFinish: (CGFloat?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let coordinator = context.coordinator
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tap))
        let hold = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 10
        hold.delegate = coordinator
        let pan = CalendarPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator
        tap.require(toFail: hold)
        tap.require(toFail: pan)
        coordinator.holdRecognizer = hold
        coordinator.panRecognizer = pan
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(pan)
        pan.isEnabled = editable && selected
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.panRecognizer?.isEnabled = editable && selected
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CalendarTimelineInteraction
        weak var holdRecognizer: UILongPressGestureRecognizer?
        weak var panRecognizer: UIPanGestureRecognizer?
        private var originY: CGFloat = 0

        init(_ parent: CalendarTimelineInteraction) { self.parent = parent }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.editable else { return false }
            if gestureRecognizer === holdRecognizer { return !parent.selected }
            return parent.selected && holdRecognizer?.state != .began && holdRecognizer?.state != .changed
        }

        @objc func tap() { parent.onTap() }

        @objc func hold(_ recognizer: UILongPressGestureRecognizer) {
            let y = recognizer.location(in: recognizer.view?.window).y
            switch recognizer.state {
            case .began:
                originY = y
                parent.onSelect()
                parent.onPreview(0)
            case .changed:
                parent.onPreview(y - originY)
            case .ended:
                parent.onFinish(y - originY)
            case .cancelled, .failed:
                parent.onFinish(nil)
            default: break
            }
        }

        @objc func pan(_ recognizer: CalendarPanGestureRecognizer) {
            let delta = recognizer.location(in: recognizer.view?.window).y - recognizer.touchDownY
            switch recognizer.state {
            case .began, .changed: parent.onPreview(delta)
            case .ended: parent.onFinish(delta)
            case .cancelled, .failed: parent.onFinish(nil)
            default: break
            }
        }
    }
}

/// Include movement before UIKit crosses its pan-recognition threshold, so
/// one hour of finger travel still means one hour of calendar movement.
final class CalendarPanGestureRecognizer: UIPanGestureRecognizer {
    private(set) var touchDownY: CGFloat = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            touchDownY = touch.location(in: view?.window).y
        }
        super.touchesBegan(touches, with: event)
    }
}
