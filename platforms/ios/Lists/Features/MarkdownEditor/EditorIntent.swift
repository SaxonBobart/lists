import Foundation

/// User-driven editor action. The coordinator translates a
/// `UITextViewDelegate` callback (or a toolbar tap, or a key
/// command) into one of these, and dispatches to the focused
/// behaviour module via `apply(to:selection:)`. Tests drive the
/// same dispatch through `EditorFixture`.
enum EditorIntent {
    case enter
    case backspace
    case forwardDelete
    case tab
    case shiftTab
    case typeText(String)
    case paste(String)
    case move(MoveDirection, MoveModifiers)
    case toolbar(ToolbarAction)
    case tapCheckbox(at: Int)
    case selectRange(NSRange)
}

enum MoveDirection: Hashable, Sendable {
    case left
    case right
    case up
    case down
    case lineHome
    case lineEnd
    case docHome
    case docEnd
}

struct MoveModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let none   = MoveModifiers([])
    static let shift  = MoveModifiers(rawValue: 1 << 0)
    static let cmd    = MoveModifiers(rawValue: 1 << 1)
    static let opt    = MoveModifiers(rawValue: 1 << 2)
}

extension EditorIntent {
    /// Pure-function dispatch: maps the intent + current state to a
    /// new state. Each case routes to the focused module that owns
    /// the behaviour. Modules expose only what the intent layer
    /// needs (e.g. `ListContinuation.apply`, `IndentHandler.indent`).
    func apply(to source: String,
               selection: NSRange) -> (source: String, selection: NSRange) {
        switch self {
        case .enter:
            return ListContinuation.apply(to: source, selection: selection)
        case .backspace:
            return BackspaceHandler.applyBackspace(to: source, selection: selection)
        case .forwardDelete:
            return BackspaceHandler.applyForwardDelete(to: source, selection: selection)
        case .tab:
            return IndentHandler.indent(source: source, selection: selection)
        case .shiftTab:
            return IndentHandler.outdent(source: source, selection: selection)
        case .typeText(let text):
            return Self.replace(in: source, selection: selection, with: text)
        case .paste(let pasted):
            return PasteHandler.apply(pasted, to: source, selection: selection)
        case .move(let direction, let modifiers):
            return CursorSnapping.move(direction: direction,
                                       modifiers: modifiers,
                                       in: source,
                                       selection: selection)
        case .toolbar(let action):
            return action.apply(to: source, selection: selection)
        case .tapCheckbox(let index):
            return CheckboxToggler.toggle(at: index, in: source, selection: selection)
        case .selectRange(let range):
            return (source, range)
        }
    }

    /// Plain-text replacement, mimicking `UITextView.insertText(_:)`'s
    /// default. No list auto-continuation, no marker suppression — the
    /// smart paths live in `ListContinuation` etc.
    private static func replace(in source: String,
                                selection: NSRange,
                                with text: String) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        let newSource = ns.replacingCharacters(in: selection, with: text)
        let newCaret = selection.location + (text as NSString).length
        return (newSource, NSRange(location: newCaret, length: 0))
    }
}
