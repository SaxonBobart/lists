import SwiftUI
import UIKit

extension Notification.Name {
    static let columnsNavigationSeparatorChanged = Notification.Name(
        "lists.columns.navigation-separator-changed"
    )
}

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
    func navigationBarTitleColor(
        _ color: Color,
        separatorVisible: Bool? = nil,
        separatorScope: String? = nil
    ) -> some View {
        background(
            NavBarTitleConfigurator(
                color: UIColor(color),
                separatorVisible: separatorVisible,
                separatorScope: separatorScope
            )
        )
    }
}

private struct NavBarTitleConfigurator: UIViewControllerRepresentable {
    let color: UIColor
    let separatorVisible: Bool?
    let separatorScope: String?

    func makeUIViewController(context: Context) -> Configurator {
        let vc = Configurator()
        vc.titleColor = color
        vc.separatorVisible = separatorVisible
        vc.separatorScope = separatorScope
        return vc
    }

    func updateUIViewController(_ uiViewController: Configurator, context: Context) {
        uiViewController.titleColor = color
        uiViewController.separatorVisible = separatorVisible
        uiViewController.separatorScope = separatorScope
        uiViewController.applyAppearance()
    }

    final class Configurator: UIViewController {
        var titleColor: UIColor = .label
        var separatorVisible: Bool?
        var separatorScope: String?
        private weak var columnsSeparatorView: UIView?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(separatorDidChange(_:)),
                name: .columnsNavigationSeparatorChanged,
                object: nil
            )
            applyAppearance()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyAppearance()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            columnsSeparatorView?.removeFromSuperview()
            columnsSeparatorView = nil
        }

        @objc private func separatorDidChange(_ notification: Notification) {
            guard let separatorScope,
                  notification.userInfo?["scope"] as? String == separatorScope,
                  let visible = notification.userInfo?["visible"] as? Bool else { return }
            separatorVisible = visible
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
            if let separatorVisible {
                // Keep the line fully native: UINavigationBar renders its
                // one-pixel shadow using the adaptive system separator color.
                appearance.shadowColor = separatorVisible ? .separator : .clear
                // Compact-height bars can retain the default material shadow
                // even with a clear tint. An empty shadow image suppresses
                // that fallback while the active column is at its top.
                appearance.shadowImage = separatorVisible ? nil : UIImage()
            }
            host.navigationItem.standardAppearance = appearance
            host.navigationItem.scrollEdgeAppearance = appearance
            host.navigationItem.compactAppearance = appearance
            host.navigationItem.compactScrollEdgeAppearance = appearance
            updateColumnsSeparatorView(on: host.navigationController?.navigationBar)
        }

        private func updateColumnsSeparatorView(on navigationBar: UINavigationBar?) {
            guard separatorScope != nil, let navigationBar else {
                columnsSeparatorView?.isHidden = true
                return
            }

            let separator: UIView
            if let columnsSeparatorView {
                separator = columnsSeparatorView
            } else {
                separator = UIView()
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.backgroundColor = .separator
                separator.isUserInteractionEnabled = false
                separator.accessibilityIdentifier = "navigation.separator.columns"
                navigationBar.addSubview(separator)
                NSLayoutConstraint.activate([
                    separator.leadingAnchor.constraint(equalTo: navigationBar.leadingAnchor),
                    separator.trailingAnchor.constraint(equalTo: navigationBar.trailingAnchor),
                    separator.bottomAnchor.constraint(equalTo: navigationBar.bottomAnchor),
                    separator.heightAnchor.constraint(
                        equalToConstant: 1 / max(1, navigationBar.traitCollection.displayScale)
                    )
                ])
                columnsSeparatorView = separator
            }
            separator.backgroundColor = .separator
            separator.isHidden = separatorVisible != true
        }
    }
}
