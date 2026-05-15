import SwiftUI

/// A wrap-flowing strip of `#tag` chips followed by a small text field for
/// adding more. Designed to sit directly under a primary title field with no
/// row separator so it reads as a sub-line, not a separate input. Tap a chip
/// to remove it; type a word + space (or comma, or Return) to commit a new
/// tag. Backspace on an empty input also drops the last chip.
///
/// Tag styling follows `feedback_tag_display` — plain `#tag` text in
/// `ListsTokens.tagAccent`, no pill background.
struct TagInputView: View {
    @Binding var tags: [String]
    var placeholder: String = "Add tag…"

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        WrapLayout(horizontalSpacing: 6, verticalSpacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    remove(tag)
                } label: {
                    Text("#\(tag)")
                        .font(.subheadline)
                        .foregroundStyle(ListsTokens.tagAccent)
                }
                .buttonStyle(.plain)
            }

            BackspaceAwareTextField(
                placeholder: placeholder,
                text: $draft,
                onBackspaceWhenEmpty: { removeLast() },
                onSubmit: { commitDraft() }
            )
            .focused($inputFocused)
            .frame(minWidth: 70)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            inputFocused = true
        }
    }

    private func commitDraft() {
        let normalized = draft.replacingOccurrences(of: ",", with: " ")
        let parts = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for word in parts {
            if let clean = Tag.sanitize(word) {
                tags = Tag.appending(clean, to: tags)
            }
        }
        draft = ""
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    private func removeLast() {
        guard !tags.isEmpty else { return }
        tags.removeLast()
    }
}

// MARK: - Backspace-aware text field

/// A UIKit-backed text field so we can detect the delete key when the field is
/// empty (SwiftUI's `TextField` doesn't expose that). Also commits the current
/// word as a tag when the user types space, comma, or Return.
private struct BackspaceAwareTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var onBackspaceWhenEmpty: () -> Void
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> _BackspaceTextField {
        let field = _BackspaceTextField()
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .subheadline)
        field.textColor = UIColor(ListsTokens.tagAccent)
        field.tintColor = UIColor(ListsTokens.tagAccent)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .done
        field.delegate = context.coordinator
        field.onBackspaceWhenEmpty = onBackspaceWhenEmpty
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: _BackspaceTextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        uiView.onBackspaceWhenEmpty = onBackspaceWhenEmpty
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        @objc func editingChanged(_ field: UITextField) {
            let current = field.text ?? ""
            text = current
            if current.contains(" ") || current.contains(",") {
                onSubmit()
            }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            onSubmit()
            return false
        }
    }
}

private final class _BackspaceTextField: UITextField {
    var onBackspaceWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            onBackspaceWhenEmpty?()
        }
        super.deleteBackward()
    }
}

// MARK: - Wrap layout

/// Tiny flow layout that places subviews left-to-right, wrapping to a new
/// line when the next subview would overflow the proposed width. Used by
/// `TagInputView` so chips wrap naturally when there are many.
struct WrapLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + horizontalSpacing + size.width > maxWidth {
                totalHeight += rowHeight + verticalSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = rowWidth == 0 ? size.width : rowWidth + horizontalSpacing + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            view.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
