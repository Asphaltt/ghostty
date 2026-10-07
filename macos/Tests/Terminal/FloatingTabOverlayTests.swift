import AppKit
import Carbon
import Combine
import SwiftUI
import Testing
@testable import Ghostty

@Suite(.serialized)
@MainActor
struct FloatingTabOverlayTests {
    private let positionDefaults = FloatingTabTestDefaults()

    @Test func positionPersistsAcrossOverlayLifetimesAndClampsOnRestore() throws {
        let window = TerminalWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let container = TerminalViewContainer { Color.clear }
        window.contentView = container
        let overlay = FloatingTabOverlay(
            window: window, container: container, defaults: positionDefaults.defaults, createTab: {}
        )
        container.layoutSubtreeIfNeeded()
        overlay.drag(by: CGSize(width: 250, height: 200))
        #expect(positionDefaults.defaults.floatingTabOrigin == nil)
        overlay.endDrag()
        let saved = try #require(positionDefaults.defaults.floatingTabOrigin)
        #expect(saved == overlay.savedPosition)
        overlay.stop()
        window.close()

        let reopened = TerminalWindow(
            contentRect: NSRect(x: 100, y: 100, width: 180, height: 160),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        reopened.isReleasedWhenClosed = false
        let reopenedContainer = TerminalViewContainer { Color.clear }
        reopened.contentView = reopenedContainer
        let reloadedDefaults = try #require(UserDefaults(suiteName: positionDefaults.suiteName))
        let restored = FloatingTabOverlay(
            window: reopened, container: reopenedContainer, defaults: reloadedDefaults, createTab: {}
        )
        defer {
            restored.stop()
            reopened.close()
        }
        reopenedContainer.layoutSubtreeIfNeeded()
        let hosting = try #require(restored.subviews.first)
        #expect(restored.savedPosition == saved)
        #expect(restored.bounds.contains(hosting.frame))
        #expect(hosting.frame.origin != saved)
        restored.endDrag()
        #expect(reloadedDefaults.floatingTabOrigin == saved)

        reopened.setContentSize(NSSize(width: 600, height: 400))
        reopenedContainer.layoutSubtreeIfNeeded()
        #expect(hosting.frame.origin == saved)

        let windowPosition = NSPoint(x: 70, y: 90)
        restored.restorePosition(windowPosition)
        reopenedContainer.layoutSubtreeIfNeeded()
        #expect(hosting.frame.origin == windowPosition)
        #expect(reloadedDefaults.floatingTabOrigin == saved)
        restored.restorePosition(NSPoint(x: CGFloat.nan, y: 0))
        #expect(restored.savedPosition == windowPosition)
    }

    @Test func invalidSavedPositionsAreIgnored() {
        let defaults = positionDefaults.defaults
        let invalidValues: [Any] = [
            "invalid", [10.0], [10.0, 20.0, 30.0], [-1.0, 20.0],
            [Double.nan, 20.0], [10.0, Double.infinity],
        ]
        for invalid in invalidValues {
            defaults.set(invalid, forKey: "floatingTabOrigin")
            #expect(defaults.floatingTabOrigin == nil)
        }
        let origin = NSPoint(x: 100, y: 80)
        defaults.floatingTabOrigin = origin
        #expect(defaults.floatingTabOrigin == origin)
        defaults.floatingTabOrigin = NSPoint(x: -1, y: 80)
        #expect(defaults.floatingTabOrigin == origin)
        defaults.floatingTabOrigin = nil
        #expect(defaults.floatingTabOrigin == nil)
    }

    @Test(arguments: ["native", "transparent"])
    func enabledByDefaultWithExplicitOptOut(titlebarStyle: String) throws {
        let config = try TemporaryConfig("macos-titlebar-style = \(titlebarStyle)")
        #expect(config.errors.isEmpty)
        #expect(FloatingTabOverlay.isEnabled(config: config, environment: [:]))
        for value in ["", "0", "false"] {
            #expect(FloatingTabOverlay.isEnabled(
                config: config,
                environment: ["GHOSTTY_FLOATING_TABS_DISABLED": value]
            ))
        }
        #expect(!FloatingTabOverlay.isEnabled(
            config: config,
            environment: ["GHOSTTY_FLOATING_TABS_DISABLED": "1"]
        ))
    }

    @Test(arguments: [
        "window-decoration = none",
        "macos-titlebar-style = tabs",
        "macos-titlebar-style = hidden",
    ])
    func unsupportedWindowStylesRemainDisabled(configText: String) throws {
        let config = try TemporaryConfig(configText)
        #expect(config.errors.isEmpty)
        #expect(!FloatingTabOverlay.isEnabled(config: config, environment: [:]))
        #expect(!FloatingTabOverlay.isEnabled(
            config: config,
            environment: ["GHOSTTY_FLOATING_TABS_DISABLED": "0"]
        ))
    }

    @Test func keyboardShortcutAndDismissalPreserveTerminalInput() throws {
        let window = TerminalWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let container = TerminalViewContainer { Color.clear }
        window.contentView = container
        let palette = CurrentValueSubject<Bool, Never>(false)
        let overlay = FloatingTabOverlay(
            window: window,
            container: container,
            commandPaletteVisibility: palette.eraseToAnyPublisher(),
            defaults: positionDefaults.defaults,
            createTab: {}
        )
        defer {
            overlay.stop()
            window.close()
        }
        func key(_ code: Int, modifiers: NSEvent.ModifierFlags = [], characters: String = "") throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: UInt16(code)
            ))
        }
        let responder = window.firstResponder
        #expect(!overlay.handleKeyDown(try key(kVK_UpArrow)))
        #expect(!overlay.handleKeyDown(try key(kVK_Delete)))
        #expect(!overlay.handleKeyDown(try key(kVK_ForwardDelete)))
        #expect(!overlay.handleKeyDown(try key(kVK_ANSI_T, modifiers: [.control, .shift], characters: "T")))
        let open = try key(kVK_ANSI_T, modifiers: .control, characters: "t")
        #expect(overlay.handleKeyDown(open))
        #expect(overlay.model.isExpanded)
        #expect(overlay.model.isKeyboardNavigating)
        #expect(window.firstResponder === responder)
        #expect(overlay.handleKeyDown(try key(kVK_DownArrow)))
        #expect(overlay.model.keyboardSelection == .newTab)
        #expect(overlay.handleKeyDown(try key(kVK_Delete)))
        #expect(overlay.handleKeyDown(try key(kVK_ForwardDelete)))
        #expect(overlay.model.keyboardSelection == .newTab)
        #expect(overlay.model.isExpanded)
        #expect(overlay.handleKeyDown(try key(kVK_Escape)))
        #expect(!overlay.model.isExpanded)
        #expect(!overlay.model.isKeyboardNavigating)

        #expect(overlay.handleKeyDown(open))
        #expect(!overlay.handleKeyDown(try key(kVK_ANSI_X, characters: "x")))
        #expect(!overlay.model.isExpanded)
        #expect(overlay.handleKeyDown(open))
        palette.send(true)
        #expect(!overlay.model.isKeyboardNavigating)
        #expect(!overlay.model.isExpanded)
    }

    @Test func tabGroupSharesPositionAndDetachMakesItIndependent() throws {
        let parent = TerminalWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let child = TerminalWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        child.isReleasedWhenClosed = false
        let parentContainer = TerminalViewContainer { Color.clear }
        let childContainer = TerminalViewContainer { Color.clear }
        parent.contentView = parentContainer
        child.contentView = childContainer
        let parentOverlay = FloatingTabOverlay(
            window: parent, container: parentContainer, defaults: positionDefaults.defaults, createTab: {}
        )
        let childOverlay = FloatingTabOverlay(
            window: child, container: childContainer, defaults: positionDefaults.defaults, createTab: {}
        )
        defer {
            parentOverlay.stop()
            childOverlay.stop()
            parent.close()
            child.close()
        }
        parentContainer.layoutSubtreeIfNeeded()
        childContainer.layoutSubtreeIfNeeded()
        let parentHosting = try #require(parentOverlay.subviews.first)
        let childHosting = try #require(childOverlay.subviews.first)
        let initial = childHosting.frame
        parentOverlay.drag(by: CGSize(width: 10_000, height: 10_000))
        parentOverlay.endDrag()
        let position = parentHosting.frame.origin
        #expect(childHosting.frame == initial)
        parentOverlay.model.isExpanded = true
        parentContainer.layoutSubtreeIfNeeded()
        #expect(parentHosting.frame.origin != position)

        parent.makeKeyAndOrderFront(nil)
        parent.addTabbedWindow(child, ordered: .above)
        parentOverlay.synchronizePosition()
        childOverlay.synchronizePosition()
        child.setContentSize(NSSize(width: 600, height: 400))
        childContainer.layoutSubtreeIfNeeded()
        #expect(childHosting.frame.origin == position)
        #expect(!childOverlay.model.isExpanded)

        parentOverlay.model.isExpanded = false
        childOverlay.drag(by: CGSize(width: -100, height: -100))
        childOverlay.endDrag()
        parentContainer.layoutSubtreeIfNeeded()
        #expect(parentHosting.frame.origin == childHosting.frame.origin)
        #expect(parentHosting.frame.origin != position)
        let sharedPosition = parentHosting.frame.origin

        child.setContentSize(NSSize(width: 180, height: 160))
        childContainer.layoutSubtreeIfNeeded()
        #expect(childOverlay.bounds.contains(childHosting.frame))
        child.setContentSize(NSSize(width: 600, height: 400))
        childContainer.layoutSubtreeIfNeeded()
        parentContainer.layoutSubtreeIfNeeded()
        #expect(childHosting.frame.origin == sharedPosition)
        #expect(parentHosting.frame.origin == sharedPosition)

        parent.tabGroup?.removeWindow(child)
        parentOverlay.synchronizePosition()
        childOverlay.synchronizePosition()
        childContainer.layoutSubtreeIfNeeded()
        #expect(childHosting.frame.origin == sharedPosition)
        childOverlay.drag(by: CGSize(width: -50, height: -50))
        childOverlay.endDrag()
        parentContainer.layoutSubtreeIfNeeded()
        #expect(parentHosting.frame.origin == sharedPosition)
        #expect(childHosting.frame.origin != sharedPosition)

        parent.addTabbedWindow(child, ordered: .above)
        parentOverlay.synchronizePosition()
        childOverlay.synchronizePosition()
        childContainer.layoutSubtreeIfNeeded()
        #expect(childHosting.frame.origin == sharedPosition)
    }

    @Test func draggingClampsAndPreservesPositionThroughExpansionAndResize() throws {
        let window = TerminalWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let container = TerminalViewContainer { Color.clear }
        window.contentView = container
        let overlay = FloatingTabOverlay(
            window: window, container: container, defaults: positionDefaults.defaults, createTab: {}
        )
        defer {
            overlay.stop()
            window.close()
        }
        container.layoutSubtreeIfNeeded()
        let hosting = try #require(overlay.subviews.first)
        let terminal = try #require(container.subviews.first)
        let terminalFrame = terminal.frame
        let initial = hosting.frame

        overlay.drag(by: CGSize(width: 120, height: 100))
        #expect(hosting.frame.origin == NSPoint(x: initial.minX + 120, y: initial.minY + 100))
        overlay.drag(by: CGSize(width: 150, height: 110))
        #expect(hosting.frame.origin == NSPoint(x: initial.minX + 150, y: initial.minY + 110))
        overlay.endDrag()
        #expect(terminal.frame == terminalFrame)

        overlay.drag(by: CGSize(width: 10_000, height: 10_000))
        overlay.endDrag()
        let bottomRight = hosting.frame
        #expect(bottomRight.maxX == overlay.bounds.maxX - FloatingTabStyle.inset)
        #expect(bottomRight.maxY == overlay.bounds.maxY - FloatingTabStyle.inset)
        overlay.model.isExpanded = true
        container.layoutSubtreeIfNeeded()
        #expect(overlay.bounds.contains(hosting.frame))
        #expect(hosting.frame.maxY == bottomRight.maxY)
        #expect(hosting.frame.minY < bottomRight.minY)
        overlay.model.isExpanded = false
        container.layoutSubtreeIfNeeded()
        #expect(hosting.frame == bottomRight)
        #expect(terminal.frame == terminalFrame)
        let outside = overlay.convert(NSPoint(x: 20, y: 20), to: container)
        #expect(overlay.hitTest(outside) == nil)
        let inside = overlay.convert(NSPoint(x: bottomRight.midX, y: bottomRight.midY), to: container)
        #expect(overlay.hitTest(inside) != nil)

        overlay.model.isExpanded = true
        container.layoutSubtreeIfNeeded()
        let expanded = hosting.frame
        overlay.drag(by: CGSize(width: -50, height: -50))
        overlay.endDrag()
        #expect(!overlay.model.isExpanded)
        #expect(hosting.frame.minX == expanded.minX - 50)
        #expect(hosting.frame.minY == bottomRight.minY - 50)

        window.setContentSize(NSSize(width: 180, height: 160))
        container.layoutSubtreeIfNeeded()
        #expect(overlay.bounds.contains(hosting.frame))
        overlay.model.isExpanded = true
        container.layoutSubtreeIfNeeded()
        #expect(overlay.bounds.contains(hosting.frame))
        overlay.drag(by: CGSize(width: -10_000, height: -10_000))
        overlay.endDrag()
        #expect(hosting.frame.origin == initial.origin)
    }

    @Test func expansionPreservesGeometryAndPassesThroughEmptySpace() throws {
        let window = TerminalWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let container = TerminalViewContainer {
            Color.clear.frame(idealWidth: 600, idealHeight: 400)
        }
        window.contentView = container
        let terminal = try #require(container.subviews.first)
        container.layoutSubtreeIfNeeded()
        let originalFrame = terminal.frame
        let originalIntrinsicSize = container.intrinsicContentSize
        let palette = CurrentValueSubject<Bool, Never>(false)
        let overlay = FloatingTabOverlay(
            window: window,
            container: container,
            commandPaletteVisibility: palette.eraseToAnyPublisher(),
            defaults: positionDefaults.defaults,
            createTab: {}
        )
        defer {
            overlay.stop()
            window.close()
        }
        overlay.layoutSubtreeIfNeeded()
        #expect(terminal.frame == originalFrame)
        #expect(container.intrinsicContentSize == originalIntrinsicSize)
        #expect(!overlay.acceptsFirstResponder)
        let outside = overlay.convert(NSPoint(x: 400, y: 300), to: container)
        #expect(overlay.hitTest(outside) == nil)
        let inside = overlay.convert(NSPoint(x: 20, y: 20), to: container)
        #expect(overlay.hitTest(inside) != nil)

        overlay.model.isExpanded = true
        container.layoutSubtreeIfNeeded()
        #expect(terminal.frame == originalFrame)
        #expect(container.intrinsicContentSize == originalIntrinsicSize)
        #expect(overlay.subviews.first?.frame.height ?? 0 > FloatingTabStyle.rowHeight)
        #expect(overlay.hitTest(outside) == nil)

        palette.send(true)
        #expect(overlay.isHidden)
        #expect(!overlay.model.isExpanded)
        palette.send(false)
        #expect(!overlay.isHidden)

        window.setContentSize(NSSize(width: 180, height: 160))
        overlay.model.isExpanded = true
        container.layoutSubtreeIfNeeded()
        #expect(overlay.bounds.contains(try #require(overlay.subviews.first).frame))
    }

    @Test func hidingAccessoryPreservesGroupAndRestoresOnStop() async throws {
        let first = TerminalWindow(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let second = NSWindow(
            contentRect: first.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        first.isReleasedWhenClosed = false
        second.isReleasedWhenClosed = false
        let container = TerminalViewContainer { Color.clear }
        first.contentView = container
        first.makeKeyAndOrderFront(nil)
        first.addTabbedWindow(second, ordered: .above)
        let overlay = FloatingTabOverlay(
            window: first, container: container, defaults: positionDefaults.defaults, createTab: {}
        )
        defer {
            overlay.stop()
            first.close()
            second.close()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let accessory = try #require(first.titlebarAccessoryViewControllers.first {
            $0.identifier == TerminalWindow.tabBarIdentifier
        })
        #expect(accessory.isHidden)
        #expect(first.tabGroup?.windows.count == 2)
        overlay.stop()
        #expect(!accessory.isHidden)
        #expect(first.tabGroup?.windows.count == 2)
        #expect(overlay.superview == nil)
    }
}

private final class FloatingTabTestDefaults {
    let suiteName = "FloatingTabOverlayTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
