import XCTest

final class GhosttyFloatingTabsUITests: GhosttyCustomConfigCase {
    override class var defaultTestSuite: XCTestSuite {
        if ProcessInfo.processInfo.environment["GHOSTTY_RUN_FLOATING_UI_TESTS"] == "1" {
            return XCTestSuite(forTestCaseClass: Self.self)
        }
        return super.defaultTestSuite
    }

    override func setUp() async throws {
        try await super.setUp()
        try updateConfig("""
        macos-titlebar-style = transparent
        window-save-state = never
        shell-integration = none
        command = /bin/sh
        confirm-close-surface = true
        """)
    }

    @MainActor
    func testKeyboardNewTabAndCloseControlsPreserveConfirmation() throws {
        let app = try ghosttyApplication()
        app.launchEnvironment["GHOSTTY_EXPERIMENTAL_FLOATING_TABS"] = "1"
        app.launch()
        defer { app.terminate() }
        let toggle = app.buttons["FloatingTabsToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        app.groups["Terminal pane"].firstMatch.hover()
        for title in ["Close first", "Close second"] {
            if title != "Close first" { app.typeKey("t", modifierFlags: .command) }
            app.typeText("printf '\\033]2;\(title)\\007'\n")
            waitUntil { toggle.value as? String == title }
        }
        let newTab = app.buttons["FloatingTabsNewTab"].firstMatch
        app.typeKey("t", modifierFlags: .control)
        waitForRows(2, in: app)
        app.typeKey(.downArrow, modifierFlags: [])
        waitUntil { newTab.value as? String == "Keyboard focused" }
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertFalse(app.sheets.firstMatch.exists)
        waitForRows(2, in: app)
        XCTAssertEqual(newTab.value as? String, "Keyboard focused")
        app.typeKey(.return, modifierFlags: [])
        app.typeText("printf '\\033]2;Close third\\007'\n")
        waitUntil { toggle.value as? String == "Close third" }

        app.typeKey("t", modifierFlags: .control)
        waitForRows(3, in: app)
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.delete, modifierFlags: [])
        let cancel = app.sheets.buttons["Cancel"]
        let confirm = app.sheets.buttons["Close"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        waitUntil { toggle.value as? String == "Close second" }
        app.typeKey("t", modifierFlags: .control)
        waitForRows(3, in: app)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()

        app.typeKey("t", modifierFlags: .control)
        waitForRows(2, in: app)
        let firstRow = app.buttons.matching(identifier: "FloatingTabRow").matching(
            NSPredicate(format: "label == %@", "Close first")
        ).firstMatch
        let closeButton = app.buttons.matching(identifier: "FloatingTabClose").matching(
            NSPredicate(format: "label == %@", "Close Close first")
        ).firstMatch
        XCTAssertFalse(closeButton.exists)
        firstRow.hover()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()

        app.typeKey("t", modifierFlags: .control)
        waitForRows(1, in: app)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        waitUntil { toggle.value as? String == "Close third" }
        app.typeKey("t", modifierFlags: .control)
        waitForRows(1, in: app)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()
        XCTAssertTrue(toggle.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testKeyboardTabManagerSelectionDismissalAndTyping() throws {
        let app = try ghosttyApplication()
        app.launchEnvironment["GHOSTTY_EXPERIMENTAL_FLOATING_TABS"] = "1"
        app.launch()
        defer { app.terminate() }
        let toggle = app.buttons["FloatingTabsToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        app.groups["Terminal pane"].firstMatch.hover()
        for title in ["Keyboard first", "Keyboard second", "Keyboard third"] {
            if title != "Keyboard first" { app.typeKey("t", modifierFlags: .command) }
            app.typeText("printf '\\033]2;\(title)\\007'\n")
            waitUntil { toggle.value as? String == title }
        }
        let newTab = app.buttons["FloatingTabsNewTab"].firstMatch
        let rows = app.buttons.matching(identifier: "FloatingTabRow")
        let firstRow = rows.matching(NSPredicate(format: "label == %@", "Keyboard first")).firstMatch
        let secondRow = rows.matching(NSPredicate(format: "label == %@", "Keyboard second")).firstMatch
        let thirdRow = rows.matching(NSPredicate(format: "label == %@", "Keyboard third")).firstMatch
        app.typeKey("t", modifierFlags: .control)
        waitForRows(3, in: app)
        waitUntil { thirdRow.value as? String == "Keyboard focused" }
        app.typeKey(.upArrow, modifierFlags: [])
        waitUntil { secondRow.value as? String == "Keyboard focused" }
        XCTAssertEqual(toggle.value as? String, "Keyboard third")
        app.typeKey(.downArrow, modifierFlags: [])
        waitUntil { thirdRow.value as? String == "Keyboard focused" }
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        waitUntil { firstRow.value as? String == "Keyboard focused" }
        app.typeKey(.return, modifierFlags: [])
        waitUntil { toggle.value as? String == "Keyboard first" }
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
        app.typeText("printf '\\033]2;Typed after keyboard selection\\007'\n")
        waitUntil { toggle.value as? String == "Typed after keyboard selection" }

        app.typeKey("t", modifierFlags: .control)
        XCTAssertTrue(newTab.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
        app.typeKey("t", modifierFlags: .control)
        XCTAssertTrue(newTab.waitForExistence(timeout: 3))
        app.typeText("printf '\\033]2;Typing dismisses manager\\007'\n")
        waitUntil { toggle.value as? String == "Typing dismisses manager" }
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testTabsShareDraggedPillPosition() throws {
        let app = try ghosttyApplication()
        app.launchEnvironment["GHOSTTY_EXPERIMENTAL_FLOATING_TABS"] = "1"
        app.launch()
        defer { app.terminate() }
        let toggle = app.buttons["FloatingTabsToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        app.typeText("printf '\\033]2;Shared first\\007'\n")
        waitUntil { toggle.value as? String == "Shared first" }
        let terminal = app.groups["Terminal pane"].firstMatch
        let newTab = app.buttons["FloatingTabsNewTab"].firstMatch
        let bottomRight = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: bottomRight)
        terminal.hover()
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
        let position = CGPoint(
            x: toggle.frame.minX - terminal.frame.minX,
            y: toggle.frame.minY - terminal.frame.minY
        )
        XCTAssertGreaterThan(position.x, terminal.frame.width / 2)
        XCTAssertGreaterThan(position.y, terminal.frame.height / 2)

        app.typeKey("t", modifierFlags: .command)
        app.typeText("printf '\\033]2;Shared second\\007'\n")
        waitUntil { toggle.value as? String == "Shared second" }
        toggle.hover()
        waitForRows(2, in: app)
        toggle.click()
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
        XCTAssertEqual(toggle.frame.minX - terminal.frame.minX, position.x, accuracy: 1)
        XCTAssertEqual(toggle.frame.minY - terminal.frame.minY, position.y, accuracy: 1)

        toggle.click()
        XCTAssertTrue(newTab.waitForExistence(timeout: 3))
        newTab.click()
        toggle.hover()
        waitForRows(3, in: app)
        toggle.click()
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
        XCTAssertEqual(toggle.frame.minX - terminal.frame.minX, position.x, accuracy: 1)
        XCTAssertEqual(toggle.frame.minY - terminal.frame.minY, position.y, accuracy: 1)

        app.typeText("printf '\\033]2;Shared third\\007'\n")
        waitUntil { toggle.value as? String == "Shared third" }
        let topLeft = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: topLeft)
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
        let movedPosition = CGPoint(
            x: toggle.frame.minX - terminal.frame.minX,
            y: toggle.frame.minY - terminal.frame.minY
        )
        XCTAssertLessThan(movedPosition.x, position.x)
        XCTAssertLessThan(movedPosition.y, position.y)
        app.typeKey("1", modifierFlags: .command)
        waitUntil { toggle.value as? String == "Shared first" }
        XCTAssertEqual(toggle.frame.minX - terminal.frame.minX, movedPosition.x, accuracy: 1)
        XCTAssertEqual(toggle.frame.minY - terminal.frame.minY, movedPosition.y, accuracy: 1)
        app.typeKey("2", modifierFlags: .command)
        waitUntil { toggle.value as? String == "Shared second" }
        XCTAssertEqual(toggle.frame.minX - terminal.frame.minX, movedPosition.x, accuracy: 1)
        XCTAssertEqual(toggle.frame.minY - terminal.frame.minY, movedPosition.y, accuracy: 1)

        let center = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.45))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: center)
        let updatedPosition = CGPoint(
            x: toggle.frame.minX - terminal.frame.minX,
            y: toggle.frame.minY - terminal.frame.minY
        )
        XCTAssertGreaterThan(updatedPosition.x, movedPosition.x)
        XCTAssertGreaterThan(updatedPosition.y, movedPosition.y)
        app.typeKey("3", modifierFlags: .command)
        waitUntil { toggle.value as? String == "Shared third" }
        XCTAssertEqual(toggle.frame.minX - terminal.frame.minX, updatedPosition.x, accuracy: 1)
        XCTAssertEqual(toggle.frame.minY - terminal.frame.minY, updatedPosition.y, accuracy: 1)
    }

    @MainActor
    func testDraggingPreservesTerminalAndKeepsExpansionInsideWindow() throws {
        let app = try ghosttyApplication()
        app.launchEnvironment["GHOSTTY_EXPERIMENTAL_FLOATING_TABS"] = "1"
        app.launch()
        defer { app.terminate() }
        let toggle = app.buttons["FloatingTabsToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let terminal = app.groups["Terminal pane"].firstMatch
        let terminalFrame = terminal.frame
        let window = app.windows.firstMatch
        let windowFrame = window.frame
        let initial = toggle.frame
        let center = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: center)
        waitUntil { toggle.frame.minX > initial.minX + 50 && toggle.frame.minY > initial.minY + 50 }
        XCTAssertEqual(terminal.frame, terminalFrame)
        XCTAssertEqual(window.frame, windowFrame)

        let bottomRight = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: bottomRight)
        terminal.hover()
        let newTab = app.buttons["FloatingTabsNewTab"].firstMatch
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
        let collapsed = toggle.frame
        XCTAssertTrue(terminalFrame.contains(collapsed))
        XCTAssertGreaterThan(collapsed.minX, terminalFrame.midX)
        XCTAssertGreaterThan(collapsed.minY, terminalFrame.midY)
        toggle.hover()
        XCTAssertTrue(newTab.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.frame.minY, collapsed.minY, accuracy: 1)
        XCTAssertTrue(terminalFrame.contains(newTab.frame))
        XCTAssertLessThan(newTab.frame.minY, toggle.frame.minY)
        XCTAssertEqual(terminal.frame, terminalFrame)
        app.typeText("printf '\\033]2;Typed after dragging\\007'\n")
        waitUntil { toggle.value as? String == "Typed after dragging" }

        let topLeft = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: topLeft)
        terminal.hover()
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
        XCTAssertEqual(toggle.frame.minX, initial.minX, accuracy: 1)
        XCTAssertEqual(toggle.frame.minY, initial.minY, accuracy: 1)
        XCTAssertEqual(window.frame, windowFrame)
        toggle.hover()
        XCTAssertTrue(newTab.waitForExistence(timeout: 3))
        toggle.click()
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
        toggle.click()
        XCTAssertTrue(newTab.waitForExistence(timeout: 3))
    }

    @MainActor
    func testHoverSelectionCreationAndTerminalGeometry() throws {
        let app = try ghosttyApplication()
        app.launchEnvironment["GHOSTTY_EXPERIMENTAL_FLOATING_TABS"] = "1"
        app.launch()
        defer { app.terminate() }
        let toggle = app.buttons["FloatingTabsToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let originalFrame = app.groups["Terminal pane"].firstMatch.frame
        toggle.hover()
        let newTab = app.buttons["FloatingTabsNewTab"].firstMatch
        XCTAssertTrue(newTab.waitForExistence(timeout: 3))
        XCTAssertEqual(app.groups["Terminal pane"].firstMatch.frame, originalFrame)
        XCTAssertEqual(app.buttons.matching(identifier: "FloatingTabRow").count, 2)
        newTab.click()
        toggle.hover()
        waitForRows(3, in: app)
        app.buttons.matching(identifier: "FloatingTabRow").element(boundBy: 0).click()
        app.typeKey("2", modifierFlags: .command)
        app.typeKey("w", modifierFlags: .command)
        let closeConfirmation = app.sheets.buttons["Close"]
        XCTAssertTrue(closeConfirmation.waitForExistence(timeout: 3))
        closeConfirmation.click()
        toggle.hover()
        waitForRows(2, in: app)
        app.groups["Terminal pane"].firstMatch.hover()
        XCTAssertTrue(newTab.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testDisabledLeavesNativeTabs() throws {
        let app = try ghosttyApplication()
        app.launch()
        defer { app.terminate() }
        let terminal = app.groups["Terminal pane"].firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 10))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: \.tabs.count, toEqual: 2, timeout: 3))
        XCTAssertFalse(app.buttons["FloatingTabsToggle"].exists)
        app.typeKey("t", modifierFlags: .control)
        XCTAssertFalse(app.buttons["FloatingTabsNewTab"].exists)
    }

    @MainActor
    func testTitlesTypingSplitsAndFullscreen() throws {
        let app = try ghosttyApplication()
        app.launchEnvironment["GHOSTTY_EXPERIMENTAL_FLOATING_TABS"] = "1"
        app.launch()
        defer { app.terminate() }
        let toggle = app.buttons["FloatingTabsToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        app.typeText("printf '\\033]2;First shell title\\007'\n")
        waitUntil { toggle.value as? String == "First shell title" }
        app.typeKey("t", modifierFlags: .command)
        app.typeText("printf '\\033]2;Second shell title\\007'\n")
        toggle.hover()
        let firstRow = app.buttons.matching(identifier: "FloatingTabRow").matching(
            NSPredicate(format: "label == %@", "First shell title")
        ).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 3))
        firstRow.click()
        app.typeText("printf '\\033]2;Typed without refocusing\\007'\n")
        waitUntil { toggle.value as? String == "Typed without refocusing" }
        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Horizontal split divider"].waitForExistence(timeout: 3))
        app.typeKey("f", modifierFlags: [.command, .control])
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.hover()
        waitForRows(2, in: app)
        app.typeKey("f", modifierFlags: [.command, .control])
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitForRows(_ count: Int, in app: XCUIApplication) {
        waitUntil {
            app.buttons.matching(identifier: "FloatingTabRow").count == count
        }
    }

    @MainActor
    private func waitUntil(_ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }
}
