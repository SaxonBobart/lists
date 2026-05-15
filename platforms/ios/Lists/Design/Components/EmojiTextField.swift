import SwiftUI
import UIKit

/// Single-character emoji input field. Bridges UIKit's `UITextField` and
/// forces the system **emoji keyboard plane** by overriding
/// `textInputMode` — the standard hack for showing the system emoji
/// picker in an app without writing a full picker view.
///
/// Usage: place anywhere with zero frame, then drive `isFocused` from a
/// button. Each typed emoji arrives via the `text` binding (one shot —
/// the field never accumulates).
struct EmojiInputField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> EmojiKeyboardTextField {
        let tf = EmojiKeyboardTextField()
        tf.delegate = context.coordinator
        tf.tintColor = .clear
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.smartInsertDeleteType = .no
        return tf
    }

    func updateUIView(_ uiView: EmojiKeyboardTextField, context: Context) {
        if isFocused, !uiView.isFirstResponder {
            // Small delay so the view is fully mounted in its window
            // before we try to grab first responder — without this the
            // first tap can silently fail when the field is inline.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                }
            }
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard !string.isEmpty else { return false }
            // Hop off the keyboard-input callback before mutating SwiftUI
            // state — touching `text` or `isFocused` synchronously here
            // can deadlock the input system on iOS 26.
            DispatchQueue.main.async { [self] in
                text = string
                isFocused = false
            }
            return false
        }

        func textFieldDidEndEditing(
            _ textField: UITextField,
            reason: UITextField.DidEndEditingReason
        ) {
            isFocused = false
        }
    }
}

/// UITextField subclass whose only job is to force the emoji input plane.
final class EmojiKeyboardTextField: UITextField {
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        for mode in UITextInputMode.activeInputModes
        where mode.primaryLanguage == "emoji" {
            return mode
        }
        return super.textInputMode
    }
}
