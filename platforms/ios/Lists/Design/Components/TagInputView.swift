import SwiftUI

/// A wrap-flowing strip of `#tag` chips followed by a small text field for
/// adding more. Tap a chip to remove it; type a word + space (or comma, or
/// Return) to commit a new tag. Backspace on an empty input also drops the
/// last chip.
///
/// Tag styling follows `feedback_tag_display` — plain `#tag` text in
/// `ListsTokens.tagAccent`, no pill background.
struct TagInputView: View {
    @Binding var tags: [String]
    var placeholder: String = "Add Tags…"
    /// Increment to programmatically focus the input field (e.g. from a "tags"
    /// toolbar button). 0 = no focus requested.
    var focusToken: Int = 0
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var draft: String = ""

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
                .accessibilityLabel("Remove #\(tag)")
                .accessibilityIdentifier("tags.remove." + tag.utf8.map { String(format: "%02x", $0) }.joined())
            }

            BackspaceAwareTextField(
                placeholder: placeholder,
                text: $draft,
                onBackspaceWhenEmpty: { removeLast() },
                onSubmit: { commitDraft() },
                focusToken: focusToken,
                onEditingChanged: onEditingChanged
            )
            .frame(minWidth: 70)
        }
        .contentShape(Rectangle())
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
    var focusToken: Int = 0
    var onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> _BackspaceTextField {
        let field = _BackspaceTextField()
        field.placeholder = placeholder
        field.accessibilityIdentifier = "tags.input"
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
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onEditingChanged = onEditingChanged
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        uiView.onBackspaceWhenEmpty = onBackspaceWhenEmpty
        // A bumped token (from a "tags" toolbar button) requests focus. The
        // field may have just been revealed, so retry once if it isn't in a
        // window yet.
        if focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
            if focusToken > 0 {
                DispatchQueue.main.async {
                    if !uiView.becomeFirstResponder() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            uiView.becomeFirstResponder()
                        }
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onEditingChanged: onEditingChanged)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var onEditingChanged: (Bool) -> Void
        var lastFocusToken = 0

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onEditingChanged: @escaping (Bool) -> Void) {
            _text = text
            self.onSubmit = onSubmit
            self.onEditingChanged = onEditingChanged
        }

        @objc func editingChanged(_ field: UITextField) {
            let current = field.text ?? ""
            text = current
            if current.contains(" ") || current.contains(",") {
                onSubmit()
            }
        }

        func textFieldDidBeginEditing(_ field: UITextField) { onEditingChanged(true) }
        func textFieldDidEndEditing(_ field: UITextField) {
            onSubmit()
            onEditingChanged(false)
        }
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            onSubmit()
            field.resignFirstResponder()
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
