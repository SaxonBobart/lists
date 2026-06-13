import UIKit

// MARK: - Placeholder text view

/// A plain `UITextView` styled to sit flush in the inline editor, with a
/// lightweight placeholder shown while empty.
final class PlaceholderTextView: UITextView {
    private let placeholderLabel = UILabel()
    /// Non-editable coloured priority prefix ("!" / "!!" / "!!!") shown ahead
    /// of the editable text, matching how `ItemRow` renders priority.
    private let prefixLabel = UILabel()
    /// Leading constraints for the placeholder + prefix, shifted by the prefix
    /// width so the editable text and placeholder begin after the prefix.
    private var placeholderLeading: NSLayoutConstraint?
    private var prefixFont: UIFont = .preferredFont(forTextStyle: .body)
    /// Last width SwiftUI proposed for self-sizing. Reused when a later layout
    /// pass proposes none, so a transient narrow width can't wrap a one-line
    /// field to two. See `InlineTextField.sizeThatFits`.
    var lastMeasuredWidth: CGFloat = 0

    func configureAsInlineField(font: UIFont, textColor: UIColor, placeholder: String) {
        self.font = font
        self.overheadCache = nil
        self.textColor = textColor
        self.prefixFont = font
        self.backgroundColor = .clear
        self.isScrollEnabled = false
        // Flush insets so the editable text lands at the same baseline as the
        // row's plain Text — any top inset would drop the title a point on edit.
        self.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        self.textContainer.lineFragmentPadding = 0
        self.setContentHuggingPriority(.defaultHigh, for: .vertical)
        self.setContentCompressionResistancePriority(.required, for: .vertical)

        prefixLabel.font = font
        prefixLabel.numberOfLines = 1
        prefixLabel.isHidden = true
        prefixLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(prefixLabel)

        placeholderLabel.text = placeholder
        placeholderLabel.font = font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        let phLeading = placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor)
        placeholderLeading = phLeading
        NSLayoutConstraint.activate([
            prefixLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            prefixLabel.topAnchor.constraint(equalTo: topAnchor),
            phLeading,
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor)
        ])
        refreshPlaceholder()
    }

    /// Show a coloured priority prefix and inset the editable text so typing
    /// begins after it (keeps the title word at the same x as the row's
    /// "!!! Title"). `nil` clears it.
    func setPriorityPrefix(_ text: String?, color: UIColor?) {
        guard let text, let color else {
            prefixLabel.isHidden = true
            prefixLabel.text = nil
            setLeftInset(0)
            return
        }
        prefixLabel.text = text
        prefixLabel.textColor = color
        prefixLabel.isHidden = false
        // Width of "prefix + space" so the editable text lands exactly where
        // the row renders the title word after the prefix.
        let width = ((text + " ") as NSString)
            .size(withAttributes: [.font: prefixFont]).width
        setLeftInset(width)
    }

    private func setLeftInset(_ left: CGFloat) {
        var inset = textContainerInset
        inset.left = left
        textContainerInset = inset
        placeholderLeading?.constant = left
    }

    func refreshPlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    /// Cached overhead, keyed by the inputs it depends on, so the per-layout
    /// probe below runs once per (font size, scale) rather than every pass.
    private var overheadCache: (pointSize: CGFloat, scale: CGFloat, value: CGFloat)?

    /// A non-scrolling `UITextView` (TextKit 2) reports a *fixed* sliver of
    /// extra height — measured ~1.67pt for `.body` at @3x — beyond the SwiftUI
    /// `Text` that the static `ItemRow` renders for the same string. The extra
    /// is empty space below the last line (constant, not per-line), so without
    /// correcting for it the title field is 1.67pt too tall, which sags the
    /// notes line — and the meta/date line below it twice over — downward the
    /// instant a row enters edit. That sag is the visible "jump."
    ///
    /// Returns that overhead so `InlineTextField.sizeThatFits` can subtract it
    /// and have the field measure exactly like the `Text` it stands in for.
    /// Derived from the live font + display scale, so it tracks Dynamic Type.
    func measuredHeightOverhead(displayScale: CGFloat) -> CGFloat {
        guard let font, displayScale > 0 else { return 0 }
        if let c = overheadCache, c.pointSize == font.pointSize, c.scale == displayScale {
            return c.value
        }
        // Measure a guaranteed single line on a throwaway view — NOT on `self`,
        // whose live text may contain hard newlines that no width can collapse
        // (measuring those here would over-report the overhead by whole lines
        // and collapse the field the moment the user adds a line). Compare that
        // against the pixel-grid-rounded font line height — exactly how SwiftUI
        // sizes a one-line `Text`.
        let oneLine = Self.singleLineHeight(font: font)
        let textLine = (font.lineHeight * displayScale).rounded(.up) / displayScale
        let value = max(0, oneLine - textLine)
        overheadCache = (font.pointSize, displayScale, value)
        return value
    }

    /// Height a non-scrolling `UITextView` reports for a single line in `font`,
    /// configured exactly as the inline fields are (flush insets, no padding).
    private static func singleLineHeight(font: UIFont) -> CGFloat {
        let probe = UITextView()
        probe.isScrollEnabled = false
        probe.textContainerInset = .zero
        probe.textContainer.lineFragmentPadding = 0
        probe.font = font
        probe.text = "X"
        return probe.sizeThatFits(CGSize(width: 100_000, height: 100_000)).height
    }

    override var text: String! {
        didSet { refreshPlaceholder() }
    }
}
