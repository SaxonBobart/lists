import SwiftUI
import UIKit

/// Hidden bridge that lets a SwiftUI sheet intercept the swipe-to-dismiss
/// gesture. When `preventDismiss` is `true` we set
/// `isModalInPresentation = true` on the sheet's view controller — that's
/// what makes UIKit actually consult the delegate — and the delegate
/// rejects the dismissal. UIKit then fires `presentationControllerDidAttempt
/// ToDismiss`, which calls `onAttempt` so the caller can show the discard
/// popover. Set `preventDismiss` back to `false` before calling
/// `dismiss()` to actually let the sheet close.
struct SheetDismissInterceptor: UIViewRepresentable {
    let preventDismiss: Bool
    let onAttempt: () -> Void

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        context.coordinator.preventDismiss = preventDismiss
        context.coordinator.onAttempt = onAttempt
        uiView.installIfNeeded()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        weak var presentedVC: UIViewController?
        var preventDismiss: Bool = false {
            didSet { presentedVC?.isModalInPresentation = preventDismiss }
        }
        var onAttempt: () -> Void = {}

        func presentationControllerShouldDismiss(_ controller: UIPresentationController) -> Bool {
            !preventDismiss
        }

        func presentationControllerDidAttemptToDismiss(_ controller: UIPresentationController) {
            onAttempt()
        }
    }

    final class BridgeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installIfNeeded()
            // SwiftUI sometimes re-asserts the presentation controller's
            // delegate after we install ours; re-install on the next runloop.
            DispatchQueue.main.async { [weak self] in
                self?.installIfNeeded()
            }
        }

        /// Walk down from the key window's root VC through chained
        /// `presentedViewController`s to find the topmost presented VC —
        /// that's the sheet. More reliable than the responder chain since
        /// SwiftUI's internal view hierarchy may short-circuit it.
        func installIfNeeded() {
            guard let coordinator else { return }
            guard let window = window ?? findKeyWindow() else { return }

            var topVC = window.rootViewController
            while let presented = topVC?.presentedViewController {
                topVC = presented
            }

            guard let vc = topVC, vc.presentingViewController != nil else { return }

            coordinator.presentedVC = vc
            vc.isModalInPresentation = coordinator.preventDismiss
            if vc.presentationController?.delegate !== coordinator {
                vc.presentationController?.delegate = coordinator
            }
        }

        private func findKeyWindow() -> UIWindow? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }
    }
}
