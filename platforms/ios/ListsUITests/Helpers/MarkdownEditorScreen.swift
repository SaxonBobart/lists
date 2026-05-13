import XCTest

/// Page-object wrapper around the live markdown editor inside the
/// running app. Every UI test that exercises the editor goes through
/// this — both to keep the test bodies readable and to make repeated
/// flows (open from a Today item, clear, type a snippet, read source)
/// resilient to navigation changes.
@MainActor
struct MarkdownEditorScreen {
    let app: XCUIApplication

    /// The underlying `UITextView` exposed by the markdown editor.
    /// Picked by accessibility id (set in `MarkdownTextView.makeUIView`).
    var editor: XCUIElement { app.textViews["markdown.editor"] }

    init(_ app: XCUIApplication) { self.app = app }

    static func launchApp(resetData: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if resetData {
            app.launchArguments.append("--ui-testing-reset-data")
        }
        app.launch()
        return app
    }

    // MARK: Open / close

    /// Stable route into the editor for tests that don't need an existing
    /// item: home → New Item → expand Notes.
    static func openFromNewItemSheet(in app: XCUIApplication,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) -> MarkdownEditorScreen {
        let add = app.descendants(matching: .any)["floating.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "New Item button never appeared", file: file, line: line)
        add.tap()

        let title = app.navigationBars["New Item"]
        XCTAssertTrue(title.waitForExistence(timeout: 5),
                      "New Item sheet never appeared", file: file, line: line)

        let expand = app.buttons["item.notes.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5),
                      "Open Markdown editor button missing on New Item sheet", file: file, line: line)
        expand.tap()

        let screen = MarkdownEditorScreen(app)
        XCTAssertTrue(screen.editor.waitForExistence(timeout: 5),
                      "Markdown editor never appeared", file: file, line: line)
        screen.focusEditor()
        screen.clear()
        return screen
    }

    /// Standard route into the editor: home → Today → first item → expand
    /// the notes field into the full-screen editor. Caller is responsible
    /// for asserting the editor exists; we just navigate.
    static func openFromFirstTodayItem(in app: XCUIApplication,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) -> MarkdownEditorScreen {
        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today'")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5),
                      "Today tile never appeared", file: file, line: line)
        today.tap()

        let item = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'item.row.task.' OR identifier BEGINSWITH 'item.row.note.'")
        )
            .firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3),
                      "No item to open in Today list", file: file, line: line)
        item.tap()

        let expand = app.buttons["item.notes.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 3),
                      "Open Markdown editor button missing on detail sheet", file: file, line: line)
        expand.tap()

        let screen = MarkdownEditorScreen(app)
        XCTAssertTrue(screen.editor.waitForExistence(timeout: 3),
                      "Markdown editor never appeared", file: file, line: line)
        screen.focusEditor()
        screen.clear()
        return screen
    }

    /// Dismiss the editor — saves whatever's in the bound notes field.
    func close() {
        app.buttons["markdown.done"].tap()
    }

    // MARK: Interaction primitives

    /// Force focus / cursor into the text view. iOS sometimes loses
    /// first responder when the test runner navigates between screens.
    func focusEditor() {
        if !editor.exists { return }
        editor.tap()
    }

    /// Wipe the editor's contents via cmd-A select-all + delete. Used
    /// in test setup so each scenario starts from a known-empty state.
    func clear() {
        guard !source.isEmpty else { return }
        editor.tap()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
    }

    func type(_ text: String) { editor.typeText(text) }
    func typeCharacters(_ text: String) {
        for character in text {
            editor.typeText(String(character))
        }
    }
    func pressReturn() { editor.typeText("\n") }
    func pressTab(shift: Bool = false) {
        editor.typeKey("\t", modifierFlags: shift ? .shift : [])
    }
    func pressKey(_ key: XCUIKeyboardKey, modifierFlags: XCUIElement.KeyModifierFlags = []) {
        editor.typeKey(key.rawValue, modifierFlags: modifierFlags)
    }

    /// Tap a button in the Apple Reminders-style accessory toolbar.
    /// The toolbar scrolls horizontally; `firstMatch` + `tap()`
    /// handles off-screen hits via XCUITest's scroll-to-visible.
    func tapToolbar(_ id: String) {
        let button = app.buttons[id].firstMatch
        if button.waitForExistence(timeout: 1) {
            button.tap()
        }
    }

    /// Set the system pasteboard and trigger paste through the edit
    /// menu. Hardware Cmd-V over XCUITest's `typeKey` is unreliable
    /// on the iOS Simulator; long-press → "Paste" hits the same
    /// `UITextView.paste(_:)` action the user would.
    func paste(_ text: String) {
        UIPasteboard.general.string = text
        editor.press(forDuration: 1.0)
        let paste = app.menuItems["Paste"].firstMatch
        if paste.waitForExistence(timeout: 2) {
            paste.tap()
        } else {
            editor.typeKey("v", modifierFlags: .command)
        }
    }

    func tapDeleteKey() {
        let delete = app.keys["delete"].firstMatch
        if delete.exists {
            delete.tap()
        } else {
            pressKey(.delete)
        }
    }

    /// Tap a visible editor line near the text column. This intentionally
    /// drives the same cursor-placement path a person uses when they go
    /// back to an existing list item and edit it.
    func tapVisibleLine(_ lineIndex: Int, xOffset: CGFloat = 104) {
        let topInset: CGFloat = 48
        let lineHeight: CGFloat = 24
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: xOffset, dy: topInset + CGFloat(lineIndex) * lineHeight))
            .tap()
    }

    // MARK: Read state

    /// Raw markdown source backing the editor. Empty string if the
    /// text view's accessibility value isn't a string yet (happens
    /// briefly during animations).
    var source: String { (editor.value as? String) ?? "" }

    /// Current selection range, read from the hidden cursor indicator
    /// element added in `MarkdownTextView`. Format on the wire is
    /// `"{location}-{length}"`. Returns `(0, 0)` if the element hasn't
    /// been attached yet (happens briefly during the editor open
    /// transition).
    var cursor: (location: Int, length: Int) {
        let raw = (app.staticTexts["markdown.editor.cursor"].value as? String) ?? "0-0"
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return (0, 0) }
        return (parts[0], parts[1])
    }
}
