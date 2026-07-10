import UIKit

/// Base class for the keyboard accessory bars: a Liquid Glass pill floating
/// above the keyboard, plus the sizing plumbing every bar needs to survive
/// being an `inputAccessoryView`.
///
/// Subclasses (`InlineEditToolbar`, `MarkdownReminderToolbar`, the document
/// title's quick bar) lay their buttons out inside `pillContent`. Sharing this
/// one base is what keeps every bar's geometry — pill height, edge insets,
/// distance from the keyboard — pixel-identical across the app.
class KeyboardGlassBar: UIView {
    /// Liquid Glass pill (iOS 26). Bar content lives in `pillContent`.
    private let pill = UIVisualEffectView(effect: UIGlassEffect())
    private var pillBottomConstraint: NSLayoutConstraint?

    static let pillHeight: CGFloat = 48
    static let buttonHeight: CGFloat = 44
    static let buttonWidth: CGFloat = 50
    static let edgeInset: CGFloat = 8
    /// Horizontal inset used by compact button rows inside the 48pt pill. The
    /// markdown bar uses its own scroll rhythm, but inline-edit bars still use
    /// this to keep active capsules visually nested inside the glass shell.
    static let buttonRowInset: CGFloat = 4
    static let keyboardVerticalInset: CGFloat = 10
    static let dockedBottomInset: CGFloat = 16

    /// The pill's content view — subclasses constrain their controls to this.
    var pillContent: UIView { pill.contentView }

    init() {
        super.init(frame: CGRect(
            x: 0, y: 0, width: 320,
            height: Self.pillHeight + Self.keyboardVerticalInset * 2
        ))
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear
        setupPill()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupPill() {
        pill.translatesAutoresizingMaskIntoConstraints = false
        // iOS 26 semantic corner configuration, NOT a manual `layer.cornerRadius`.
        // A glass `UIVisualEffectView` rounded by hand loses its corners when the
        // system snapshots the bar for a context-menu / sheet morph — that was the
        // whole-bar "flash square then snap back to rounded" during a menu open.
        // `cornerConfiguration` is understood semantically and survives the morph.
        pill.cornerConfiguration = .capsule()
        pill.clipsToBounds = true
        addSubview(pill)

        // Pin to the safe area so the pill clears the home indicator when the
        // bar docks at the screen edge (keyboard dismissed / hardware kbd). This
        // yields to the fixed height + top constraints: if the input system
        // doesn't re-query our grown intrinsic height in time, the bar falls
        // back to a slight clip rather than crushing the pill to fit.
        let pillBottom = pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset)
        pillBottom.priority = .required - 1
        pillBottomConstraint = pillBottom

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.edgeInset),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.edgeInset),
            pill.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: Self.keyboardVerticalInset),
            pillBottom,
            pill.heightAnchor.constraint(equalToConstant: Self.pillHeight)
        ])
    }

    // An input accessory view doesn't auto-inset for the home indicator, so it
    // gets clipped when docked at the bottom with no keyboard. Grow the bar's
    // intrinsic height by the bottom safe-area inset (0 while the keyboard is up,
    // since the keyboard then covers that zone) and lay the pill out against the
    // safe area, so the pill always sits fully above the indicator.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: preferredHeight)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        syncHeightWithSafeArea()
        invalidateIntrinsicContentSize()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncHeightWithSafeArea()
    }

    private var preferredHeight: CGFloat {
        Self.pillHeight + Self.keyboardVerticalInset + bottomInset
    }

    private var bottomInset: CGFloat {
        safeAreaInsets.bottom > 0 ? Self.dockedBottomInset : Self.keyboardVerticalInset
    }

    private func syncHeightWithSafeArea() {
        pillBottomConstraint?.constant = -bottomInset
        let height = preferredHeight
        guard frame.height != height else { return }
        frame.size.height = height
        superview?.setNeedsLayout()
    }

    // MARK: Shared button styling

    /// Pill-shaped glyph button for a glass bar. `cornerStyle = .capsule` shapes
    /// the resting and active (filled) backgrounds; `baseForegroundColor` forces
    /// every symbol (including multi-colour ones like `calendar.badge.clock`) to
    /// tint cleanly, so active glyphs read white on the blue fill.
    ///
    /// `width` defaults to the shared `buttonWidth`; a bar that packs many
    /// buttons (the inline-edit toolbar) passes a narrower width so adjacent
    /// active (blue) fills clear each other, while the end buttons still nestle
    /// into the pill's corners (the row stays pinned at the concentric inset).
    func configureCircularButton(_ button: UIButton, symbol: String, id: String,
                                 width: CGFloat = KeyboardGlassBar.buttonWidth) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol)
        config.cornerStyle = .capsule
        config.baseForegroundColor = .label
        config.background.backgroundColor = .clear
        button.configuration = config
        button.accessibilityIdentifier = id
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: Self.buttonHeight)
        ])
    }

    /// Swap a bar button's glyph while preserving its configuration.
    /// (Use this instead of `setImage(_:for:)` — a configured button ignores
    /// the legacy image API.)
    func setButtonSymbol(_ button: UIButton, _ symbol: String) {
        var config = button.configuration ?? .plain()
        config.image = UIImage(systemName: symbol)
        button.configuration = config
    }

    /// Toggle a button's filled-capsule "attribute is set" treatment.
    func setActive(_ button: UIButton, _ active: Bool) {
        var config = button.configuration ?? .plain()
        config.background.backgroundColor = active ? .systemBlue : .clear
        config.baseForegroundColor = active ? .white : .label
        button.configuration = config
    }
}
