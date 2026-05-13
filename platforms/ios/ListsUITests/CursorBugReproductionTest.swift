import XCTest

/// Test to reproduce the cursor bug when typing bullet lists and using arrow keys
final class CursorBugReproductionTest: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    private func openEditor() -> MarkdownEditorScreen {
        let app = MarkdownEditorScreen.launchApp()
        return MarkdownEditorScreen.openFromNewItemSheet(in: app)
    }
    
    @MainActor
    func testBulletListWithArrowKeyNavigation() {
        let screen = openEditor()
        
        // Type a bullet list: "- first"
        screen.typeCharacters("-")
        screen.typeCharacters(" ")
        screen.typeCharacters("f")
        screen.typeCharacters("i")
        screen.typeCharacters("r")
        screen.typeCharacters("s")
        screen.typeCharacters("t")
        
        // Check source
        let afterFirst = screen.source
        print("After typing '- first': '\(afterFirst)'")
        XCTAssertEqual(afterFirst, "- first", "First line source should be '- first'")
        
        // Press Return to auto-continue bullet
        screen.pressReturn()
        
        let afterReturn = screen.source
        print("After pressing Return: '\(afterReturn)'")
        // Should now have "- first\n- " with cursor after "- "
        
        // Type second item
        screen.typeCharacters("s")
        screen.typeCharacters("e")
        screen.typeCharacters("c")
        screen.typeCharacters("o")
        screen.typeCharacters("n")
        screen.typeCharacters("d")
        
        let afterSecond = screen.source
        print("After typing 'second': '\(afterSecond)'")
        XCTAssertEqual(afterSecond, "- first\n- second", "Should have two bullet items")
        
        // Now test arrow key navigation - go left 6 times
        for i in 1...6 {
            screen.pressKey(.left)
            print("After Left press \(i): source = '\(screen.source)'")
        }
        
        // Go up to previous line
        screen.pressKey(.up)
        print("After Up press: source = '\(screen.source)'")
        
        // Try left/right on previous line
        screen.pressKey(.left)
        print("After Left on prev line: source = '\(screen.source)'")
        
        screen.pressKey(.right)
        print("After Right on prev line: source = '\(screen.source)'")
    }
    
    @MainActor
    func testTaskCheckboxWithArrowKeyNavigation() {
        let screen = openEditor()
        
        // Type a task checkbox: "- [ ] task"
        screen.typeCharacters("-")
        screen.typeCharacters(" ")
        screen.typeCharacters("[")
        screen.typeCharacters(" ")
        screen.typeCharacters("]")
        screen.typeCharacters(" ")
        screen.typeCharacters("t")
        screen.typeCharacters("a")
        screen.typeCharacters("s")
        screen.typeCharacters("k")
        
        let afterTask = screen.source
        print("After typing task: '\(afterTask)'")
        XCTAssertEqual(afterTask, "- [ ] task", "First task line should be '- [ ] task'")
        
        // Press Return to auto-continue
        screen.pressReturn()
        
        let afterTaskReturn = screen.source
        print("After task Return: '\(afterTaskReturn)'")
        
        // Type on new task line
        screen.typeCharacters("n")
        screen.typeCharacters("e")
        screen.typeCharacters("w")
        
        let afterNewTask = screen.source
        print("After typing 'new': '\(afterNewTask)'")
        
        // Navigate with arrow keys
        for i in 1...3 {
            screen.pressKey(.left)
            print("After Left press \(i): source = '\(screen.source)'")
        }
        
        // Go to previous line
        screen.pressKey(.up)
        print("After Up to first task: source = '\(screen.source)'")
    }
}
