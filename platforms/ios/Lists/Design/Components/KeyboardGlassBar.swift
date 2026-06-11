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

    static let pillHeight: CGFloat = 44
    static let buttonSize: CGFloat = 38
    static let edgeInset: CGFloat = 16
    static let keyboardVerticalInset: CGFloat = 8
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
        pill.layer.cornerRadius = Self.pillHeight / 2
        pill.layer.cornerCurve = .continuous
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

    /// Standard circular glyph button for a glass bar.
    func configureCircularButton(_ button: UIButton, symbol: String, id: String) {
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.accessibilityIdentifier = id
        button.layer.cornerRadius = Self.buttonSize / 2
        button.layer.cornerCurve = .continuous
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            button.heightAnchor.constraint(equalToConstant: Self.buttonSize)
        ])
    }

    /// Toggle a button's filled-circle "attribute is set" treatment.
    func setActive(_ button: UIButton, _ active: Bool) {
        button.backgroundColor = active ? .systemBlue : .clear
        button.tintColor = active ? .white : .label
    }
}
