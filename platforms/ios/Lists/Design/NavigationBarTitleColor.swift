import SwiftUI
import UIKit

/// Applies a per-view UINavigationItem appearance so that the navigation
/// bar's title (both inline and large) renders in the supplied color,
/// without leaking the appearance to other screens. Walks up to the
/// SwiftUI host's parent UIViewController and writes its `navigationItem`
/// appearances directly — those are scoped to that view controller's
/// stack frame.
///
/// Used to colour each list / smart-list screen's title in its own
/// accent (e.g. Inbox = blue title, Today = blue title, Work = orange
/// title). Adapted from the archive's modifier; uses the default
/// system font (no SF Rounded) so it matches the app-wide
/// `.fontDesign(.default)`.
extension View {
    func navigationBarTitleColor(_ color: Color) -> some View {
        background(NavBarTitleConfigurator(color: UIColor(color)))
    }
}

private struct NavBarTitleConfigurator: UIViewControllerRepresentable {
    let color: UIColor

    func makeUIViewController(context: Context) -> Configurator {
        let vc = Configurator()
        vc.titleColor = color
        return vc
    }

    func updateUIViewController(_ uiViewController: Configurator, context: Context) {
        uiViewController.titleColor = color
        uiViewController.applyAppearance()
    }

    final class Configurator: UIViewController {
        var titleColor: UIColor = .label

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            applyAppearance()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyAppearance()
        }

        fileprivate func applyAppearance() {
            guard let host = self.parent else { return }
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.largeTitleTextAttributes = [
                .font: UIFont.systemFont(ofSize: 34, weight: .bold),
                .foregroundColor: titleColor
            ]
            appearance.titleTextAttributes = [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: titleColor
            ]
            host.navigationItem.standardAppearance = appearance
            host.navigationItem.scrollEdgeAppearance = appearance
            host.navigationItem.compactAppearance = appearance
            host.navigationItem.compactScrollEdgeAppearance = appearance
        }
    }
}
