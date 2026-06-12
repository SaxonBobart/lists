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

    override var text: String! {
        didSet { refreshPlaceholder() }
    }
}
