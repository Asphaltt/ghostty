import AppKit
import Testing
@testable import Ghostty

@Suite(.serialized)
@MainActor
struct FloatingTabModelTests {
    private func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 250),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = title
        return window
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(condition())
    }

    @Test func singleWindowAndLiveTitle() async throws {
        let window = makeWindow(title: "Original")
        let model = FloatingTabModel(window: window, createTab: {})
        defer {
            model.stop()
            window.close()
        }
        #expect(model.items == [.init(id: ObjectIdentifier(window), title: "Original", selected: true)])
        window.title = "Shell title"
        try await waitFor { model.selectedTitle == "Shell title" }
        #expect(model.items.count == 1)
    }

    @Test func keyboardNavigationHighlightsWithoutSwitchingUntilActivation() async throws {
        let first = makeWindow(title: "First")
        let second = makeWindow(title: "Second")
        let third = makeWindow(title: "Third")
        let model = FloatingTabModel(window: first, createTab: {})
        defer {
            model.stop()
            first.close()
            second.close()
            third.close()
        }
        first.makeKeyAndOrderFront(nil)
        first.addTabbedWindow(second, ordered: .above)
        second.addTabbedWindow(third, ordered: .above)
        second.makeKeyAndOrderFront(nil)
        try await waitFor { model.items.count == 3 && model.selectedTitle == "Second" }

        model.openFromKeyboard()
        #expect(model.isExpanded)
        #expect(model.keyboardSelection == .tab(ObjectIdentifier(second)))
        model.moveKeyboardSelection(by: 1)
        #expect(model.keyboardSelection == .tab(ObjectIdentifier(third)))
        #expect(first.tabGroup?.selectedWindow === second)
        model.moveKeyboardSelection(by: 1)
        #expect(model.keyboardSelection == .newTab)
        model.moveKeyboardSelection(by: 1)
        #expect(model.keyboardSelection == .newTab)
        model.moveKeyboardSelection(by: -1)
        #expect(model.keyboardSelection == .tab(ObjectIdentifier(third)))
        model.moveKeyboardSelection(by: -1)
        #expect(model.keyboardSelection == .tab(ObjectIdentifier(second)))
        model.moveKeyboardSelection(by: -1)
        model.moveKeyboardSelection(by: -1)
        #expect(model.keyboardSelection == .tab(ObjectIdentifier(first)))
        #expect(first.tabGroup?.selectedWindow === second)
        model.activateKeyboardSelection()
        try await waitFor { first.tabGroup?.selectedWindow === first }
        #expect(!model.isExpanded)
        #expect(!model.isKeyboardNavigating)

        model.openFromKeyboard()
        model.moveKeyboardSelection(by: 1)
        first.tabGroup?.removeWindow(second)
        try await waitFor { model.items.count == 2 }
        #expect(model.keyboardSelection == .tab(ObjectIdentifier(first)))
        model.isExpanded = false
        #expect(!model.isKeyboardNavigating)
    }

    @Test func keyboardNewTabAndCloseDelegateOnlyForCurrentGroupMembers() async throws {
        let first = makeWindow(title: "First")
        let second = makeWindow(title: "Second")
        let unrelated = makeWindow(title: "Unrelated")
        var creations = 0
        var closeRequests: [ObjectIdentifier] = []
        let model = FloatingTabModel(
            window: first,
            closeTab: { closeRequests.append(ObjectIdentifier($0)) },
            createTab: { creations += 1 }
        )
        defer {
            model.stop()
            first.close()
            second.close()
            unrelated.close()
        }
        first.makeKeyAndOrderFront(nil)
        first.addTabbedWindow(second, ordered: .above)
        first.makeKeyAndOrderFront(nil)
        try await waitFor { model.items.count == 2 && model.selectedTitle == "First" }
        model.openFromKeyboard()
        model.moveKeyboardSelection(by: 2)
        #expect(model.keyboardSelection == .newTab)
        model.closeKeyboardSelection()
        #expect(closeRequests.isEmpty)
        #expect(model.isKeyboardNavigating)
        model.activateKeyboardSelection()
        #expect(creations == 1)
        #expect(!model.isExpanded)

        model.openFromKeyboard()
        model.moveKeyboardSelection(by: 1)
        #expect(model.keyboardSelection == .tab(ObjectIdentifier(second)))
        model.closeKeyboardSelection()
        #expect(closeRequests == [ObjectIdentifier(second)])
        #expect(!model.isExpanded)
        #expect(first.tabGroup?.windows.count == 2)
        #expect(first.tabGroup?.selectedWindow === second)
        model.close(.init(id: ObjectIdentifier(unrelated), title: "Unrelated", selected: false))
        #expect(closeRequests.count == 1)

        let stale = try #require(model.items.first { $0.id == ObjectIdentifier(second) })
        first.tabGroup?.removeWindow(second)
        model.close(stale)
        #expect(closeRequests.count == 1)
        model.stop()
        model.close(try #require(model.items.first))
        #expect(closeRequests.count == 1)
    }

    @Test func membershipSelectionTitlesAndDetach() async throws {
        let first = makeWindow(title: "First")
        let second = makeWindow(title: "Second")
        let model = FloatingTabModel(window: first, createTab: {})
        defer {
            model.stop()
            first.close()
            second.close()
        }
        first.makeKeyAndOrderFront(nil)
        first.addTabbedWindow(second, ordered: .above)
        second.makeKeyAndOrderFront(nil)
        try await waitFor { model.items.count == 2 && model.selectedTitle == "Second" }
        #expect(model.items.map(\.id) == [ObjectIdentifier(first), ObjectIdentifier(second)])

        first.title = "Background title"
        try await waitFor { model.items.first?.title == "Background title" }
        first.tabGroup?.selectedWindow = first
        try await waitFor { model.selectedTitle == "Background title" }

        model.isExpanded = true
        model.select(try #require(model.items.last))
        try await waitFor { first.tabGroup?.selectedWindow === second }
        #expect(!model.isExpanded)

        first.tabGroup?.removeWindow(second)
        first.makeKeyAndOrderFront(nil)
        try await waitFor { model.items.count == 1 && model.items.first?.id == ObjectIdentifier(first) }
    }

    @Test func staleSelectionAndNewTabDelegation() async throws {
        let window = makeWindow(title: "Only tab")
        let unrelated = makeWindow(title: "Other window")
        var creations = 0
        let model = FloatingTabModel(window: window) { creations += 1 }
        defer {
            model.stop()
            window.close()
            unrelated.close()
        }
        model.select(.init(id: ObjectIdentifier(unrelated), title: "Stale entry", selected: false))
        #expect(model.items.count == 1)
        #expect(!unrelated.isVisible)
        model.isExpanded = true
        model.newTab()
        #expect(creations == 1)
        #expect(!model.isExpanded)
    }

    @Test func movingObservedWindowRebindsToNewGroup() async throws {
        let first = makeWindow(title: "Old group")
        let moving = makeWindow(title: "Moving")
        let destination = makeWindow(title: "New group")
        let model = FloatingTabModel(window: moving, createTab: {})
        defer {
            model.stop()
            first.close()
            moving.close()
            destination.close()
        }
        first.makeKeyAndOrderFront(nil)
        first.addTabbedWindow(moving, ordered: .above)
        moving.makeKeyAndOrderFront(nil)
        try await waitFor { model.items.count == 2 }
        destination.makeKeyAndOrderFront(nil)
        destination.addTabbedWindow(moving, ordered: .above)
        moving.makeKeyAndOrderFront(nil)
        try await waitFor {
            model.items.map(\.id) == [ObjectIdentifier(destination), ObjectIdentifier(moving)]
        }
        destination.title = "New background title"
        first.title = "Old background title"
        try await waitFor { model.items.first?.title == "New background title" }
        #expect(!model.items.contains(where: { $0.id == ObjectIdentifier(first) }))
        destination.close()
        try await waitFor { model.items.count == 1 && model.selectedTitle == "Moving" }
    }

    @Test func stopCancelsQueuedRefreshAndReleasesWindow() async throws {
        var window: NSWindow? = makeWindow(title: "Initial")
        weak var weakWindow = window
        let model = FloatingTabModel(window: try #require(window), createTab: {})
        window?.title = "Queued title"
        model.stop()
        window?.close()
        window = nil
        try await waitFor { weakWindow == nil }
        #expect(model.selectedTitle == "Initial")
        #expect(weakWindow == nil)
    }
}
