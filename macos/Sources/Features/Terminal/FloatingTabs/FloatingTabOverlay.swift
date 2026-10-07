import AppKit
import Carbon
import Combine
import SwiftUI

final class FloatingTabOverlay: NSView {
    private static let positions = NSMapTable<NSWindowTabGroup, FloatingTabPosition>.weakToStrongObjects()

    static func isEnabled(
        config: Ghostty.Config,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["GHOSTTY_FLOATING_TABS_DISABLED"] != "1" &&
            config.windowDecorations &&
            (config.macosTitlebarStyle == .native || config.macosTitlebarStyle == .transparent)
    }

    let model: FloatingTabModel
    private let hostingView: FloatingTabHostingView
    private let defaults: UserDefaults
    private weak var terminalWindow: TerminalWindow?
    private var cancellables: Set<AnyCancellable> = []
    private let hiddenAccessories = NSHashTable<NSTitlebarAccessoryViewController>.weakObjects()
    private var position: FloatingTabPosition
    private weak var positionGroup: NSWindowTabGroup?
    private var positionObservation: AnyCancellable?
    private var dragOrigin: NSPoint?
    private var eventMonitor: Any?
    private var consumedKeyCodes: Set<UInt16> = []

    init(
        window: TerminalWindow,
        container: TerminalViewContainer,
        commandPaletteVisibility: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher(),
        defaults: UserDefaults = .ghostty,
        createTab: @escaping () -> Void
    ) {
        let model = FloatingTabModel(window: window, createTab: createTab)
        self.model = model
        self.hostingView = FloatingTabHostingView(rootView: FloatingTabView(model: model))
        self.defaults = defaults
        self.position = FloatingTabPosition(
            origin: defaults.floatingTabOrigin ?? NSPoint(x: FloatingTabStyle.inset, y: FloatingTabStyle.inset)
        )
        self.terminalWindow = window
        super.init(frame: container.bounds)
        hostingView.rootView.onDrag = { [weak self] translation in
            self?.drag(by: translation)
        }
        hostingView.rootView.onDragEnded = { [weak self] in
            self?.endDrag()
        }
        autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        addSubview(hostingView)
        container.addSubview(self, positioned: .above, relativeTo: nil)

        model.objectWillChange.sink { [weak self] in
            self?.needsLayout = true
        }.store(in: &cancellables)
        model.didRefresh = { [weak self] in
            self?.synchronizePosition()
            self?.syncNativeTabBar()
        }
        commandPaletteVisibility.sink { [weak self] showing in
            self?.isHidden = showing
            if showing { self?.model.isExpanded = false }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: window)
            .sink { [weak self] _ in self?.model.isExpanded = false }
            .store(in: &cancellables)
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handleEvent(event)
        }
        synchronizePosition()
        syncNativeTabBar()
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func layout() {
        super.layout()
        synchronizePosition()
        let available = availableBounds
        let headerHeight = min(FloatingTabStyle.rowHeight, available.height)
        let pillOrigin = boundedOrigin(position.origin)
        let width = min(
            model.isExpanded ? FloatingTabStyle.expandedWidth : FloatingTabStyle.collapsedWidth,
            available.width
        )
        let desiredListHeight = min(
            CGFloat(model.items.count) * FloatingTabStyle.rowHeight, FloatingTabStyle.maximumListHeight
        )
        let desiredContentHeight = headerHeight + desiredListHeight + 2
        let below = available.maxY - pillOrigin.y - headerHeight
        let above = pillOrigin.y - available.minY
        let expandsUpward = below < desiredContentHeight && above > below
        let contentHeight = model.isExpanded ? min(desiredContentHeight, expandsUpward ? above : below) : 0
        let headerOffset = expandsUpward ? contentHeight : 0
        if hostingView.rootView.headerOffset != headerOffset {
            hostingView.rootView.headerOffset = headerOffset
        }
        hostingView.frame = NSRect(
            x: min(pillOrigin.x, available.maxX - width),
            y: pillOrigin.y - headerOffset,
            width: width,
            height: headerHeight + contentHeight
        )
    }

    func drag(by translation: CGSize) {
        synchronizePosition()
        if dragOrigin == nil {
            dragOrigin = NSPoint(
                x: hostingView.frame.minX,
                y: hostingView.frame.minY + hostingView.rootView.headerOffset
            )
            model.isExpanded = false
        }
        guard let dragOrigin else { return }
        position.origin = boundedOrigin(NSPoint(
            x: dragOrigin.x + translation.width,
            y: dragOrigin.y + translation.height
        ))
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func endDrag() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        defaults.floatingTabOrigin = position.origin
    }

    var savedPosition: NSPoint {
        synchronizePosition()
        return position.origin
    }

    func restorePosition(_ origin: NSPoint) {
        guard origin.x.isFinite, origin.y.isFinite, origin.x >= 0, origin.y >= 0 else { return }
        synchronizePosition()
        position.origin = origin
    }

    func synchronizePosition() {
        let group = terminalWindow?.tabGroup
        guard positionObservation == nil || positionGroup !== group else { return }
        if let group, let sharedPosition = Self.positions.object(forKey: group) {
            position = sharedPosition
        } else {
            position = FloatingTabPosition(origin: position.origin)
            if let group { Self.positions.setObject(position, forKey: group) }
        }
        positionGroup = group
        positionObservation = position.$origin.sink { [weak self] _ in
            self?.needsLayout = true
            self?.terminalWindow?.invalidateRestorableState()
        }
    }

    func hideNativeTabBar(_ accessory: NSTitlebarAccessoryViewController) {
        if !accessory.isHidden {
            hiddenAccessories.add(accessory)
            accessory.isHidden = true
        }
    }

    func stop() {
        model.stop()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        consumedKeyCodes.removeAll()
        positionObservation = nil
        cancellables.removeAll()
        for accessory in hiddenAccessories.allObjects { accessory.isHidden = false }
        hiddenAccessories.removeAllObjects()
        removeFromSuperview()
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyUp {
            return consumedKeyCodes.remove(event.keyCode) == nil ? event : nil
        }
        guard let terminalWindow, event.window === terminalWindow,
              terminalWindow.isKeyWindow, terminalWindow.attachedSheet == nil,
              !isHidden else { return event }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if model.isKeyboardNavigating,
               !hostingView.frame.contains(convert(event.locationInWindow, from: nil)) {
                model.isExpanded = false
            }
            return event
        }
        guard terminalWindow.firstResponder is Ghostty.SurfaceView else {
            if model.isKeyboardNavigating { model.isExpanded = false }
            return event
        }
        if handleKeyDown(event) {
            consumedKeyCodes.insert(event.keyCode)
            return nil
        }
        return event
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if modifiers == .control, event.characters(byApplyingModifiers: [])?.lowercased() == "t" {
            if !event.isARepeat { model.openFromKeyboard() }
            return true
        }
        guard model.isKeyboardNavigating else { return false }
        if modifiers.isEmpty {
            switch Int(event.keyCode) {
            case kVK_UpArrow:
                model.moveKeyboardSelection(by: -1)
                return true
            case kVK_DownArrow:
                model.moveKeyboardSelection(by: 1)
                return true
            case kVK_Return, kVK_ANSI_KeypadEnter:
                model.activateKeyboardSelection()
                return true
            case kVK_Delete, kVK_ForwardDelete:
                if !event.isARepeat { model.closeKeyboardSelection() }
                return true
            case kVK_Escape:
                model.isExpanded = false
                return true
            default:
                break
            }
        }
        model.isExpanded = false
        return false
    }

    private var availableBounds: NSRect {
        bounds.insetBy(
            dx: min(FloatingTabStyle.inset, bounds.width / 2),
            dy: min(FloatingTabStyle.inset, bounds.height / 2)
        )
    }

    private func boundedOrigin(_ origin: NSPoint) -> NSPoint {
        let available = availableBounds
        return NSPoint(
            x: min(max(origin.x, available.minX), available.maxX - min(FloatingTabStyle.collapsedWidth, available.width)),
            y: min(max(origin.y, available.minY), available.maxY - min(FloatingTabStyle.rowHeight, available.height))
        )
    }

    private func syncNativeTabBar() {
        guard let terminalWindow else { return }
        for accessory in terminalWindow.titlebarAccessoryViewControllers
            where accessory.identifier == TerminalWindow.tabBarIdentifier {
            hideNativeTabBar(accessory)
        }
    }
}

private final class FloatingTabPosition {
    @Published var origin: NSPoint

    init(origin: NSPoint = NSPoint(x: FloatingTabStyle.inset, y: FloatingTabStyle.inset)) {
        self.origin = origin
    }
}

private final class FloatingTabHostingView: NSHostingView<FloatingTabView> {
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
}
