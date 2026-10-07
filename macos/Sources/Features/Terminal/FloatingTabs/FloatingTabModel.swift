import AppKit
import Combine

struct FloatingTabItem: Identifiable, Equatable {
    let id: ObjectIdentifier
    let title: String
    let selected: Bool
}

final class FloatingTabModel: ObservableObject {
    enum KeyboardSelection: Hashable {
        case tab(ObjectIdentifier)
        case newTab
    }

    @Published private(set) var items: [FloatingTabItem] = []
    @Published var isExpanded = false {
        didSet {
            if !isExpanded { keyboardSelection = nil }
        }
    }
    @Published private(set) var keyboardSelection: KeyboardSelection?

    var isKeyboardNavigating: Bool { keyboardSelection != nil }

    var didRefresh: (() -> Void)?
    private weak var window: NSWindow?
    private weak var observedGroup: NSWindowTabGroup?
    private var windowObservation: NSKeyValueObservation?
    private var groupObservations: [NSKeyValueObservation] = []
    private var titleObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var notifications: [NSObjectProtocol] = []
    private var refreshPending = false
    private var stopped = false
    private let createTab: () -> Void
    private let closeTab: (NSWindow) -> Void

    var selectedTitle: String {
        items.first(where: \.selected)?.title ?? window?.title ?? ""
    }

    init(
        window: NSWindow,
        closeTab: @escaping (NSWindow) -> Void = { ($0.windowController as? TerminalController)?.closeTab(nil) },
        createTab: @escaping () -> Void
    ) {
        self.window = window
        self.createTab = createTab
        self.closeTab = closeTab
        windowObservation = window.observe(\.tabGroup, options: [.new]) { [weak self] _, _ in
            self?.scheduleRefresh()
        }
        for name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.willCloseNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ] {
            notifications.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self, let changedWindow = notification.object as? NSWindow else { return }
                guard changedWindow === self.window ||
                        self.items.contains(where: { $0.id == ObjectIdentifier(changedWindow) }) else { return }
                self.scheduleRefresh()
            })
        }
        refresh()
    }

    deinit {
        notifications.forEach(NotificationCenter.default.removeObserver)
    }

    func stop() {
        stopped = true
        isExpanded = false
        windowObservation = nil
        groupObservations.removeAll()
        titleObservations.removeAll()
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications.removeAll()
        didRefresh = nil
    }

    func select(_ item: FloatingTabItem) {
        guard let window,
              let target = (window.tabGroup?.windows ?? [window]).first(where: {
                  ObjectIdentifier($0) == item.id
              }) else { return }
        isExpanded = false
        target.makeKeyAndOrderFront(nil)
        scheduleRefresh()
    }

    func newTab() {
        isExpanded = false
        createTab()
    }

    func close(_ item: FloatingTabItem) {
        guard !stopped, let window,
              let target = (window.tabGroup?.windows ?? [window]).first(where: {
                  ObjectIdentifier($0) == item.id
              }) else { return }
        isExpanded = false
        target.makeKeyAndOrderFront(nil)
        closeTab(target)
        scheduleRefresh()
    }

    private var selectedKeyboardTarget: KeyboardSelection {
        (items.first(where: \.selected) ?? items.first).map { .tab($0.id) } ?? .newTab
    }

    func openFromKeyboard() {
        guard !stopped else { return }
        refresh()
        keyboardSelection = selectedKeyboardTarget
        isExpanded = true
    }

    func moveKeyboardSelection(by offset: Int) {
        guard let keyboardSelection else { return }
        let targets = items.map { KeyboardSelection.tab($0.id) } + [.newTab]
        let index = targets.firstIndex(of: keyboardSelection) ?? 0
        self.keyboardSelection = targets[min(max(index + offset, 0), targets.count - 1)]
    }

    func activateKeyboardSelection() {
        if keyboardSelection == .newTab {
            newTab()
            return
        }
        guard case let .tab(identifier)? = keyboardSelection,
              let item = items.first(where: { $0.id == identifier }) else {
            isExpanded = false
            return
        }
        select(item)
    }

    func closeKeyboardSelection() {
        guard case let .tab(identifier)? = keyboardSelection,
              let item = items.first(where: { $0.id == identifier }) else { return }
        close(item)
    }

    func scheduleRefresh() {
        guard !stopped, !refreshPending else { return }
        refreshPending = true
        // Rebinding inside AppKit's KVO callback can retain closed windows.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.refresh()
        }
    }

    private func refresh() {
        guard !stopped, let window else { return }
        let group = window.tabGroup
        if observedGroup !== group {
            groupObservations.removeAll()
            observedGroup = group
            if let group {
                groupObservations = [
                    group.observe(\.windows, options: [.new]) { [weak self] _, _ in
                        self?.scheduleRefresh()
                    },
                    group.observe(\.selectedWindow, options: [.new]) { [weak self] _, _ in
                        self?.scheduleRefresh()
                    },
                ]
            }
        }

        let windows = group?.windows ?? [window]
        let identifiers = Set(windows.map(ObjectIdentifier.init))
        titleObservations = titleObservations.filter { identifiers.contains($0.key) }
        for member in windows where titleObservations[ObjectIdentifier(member)] == nil {
            titleObservations[ObjectIdentifier(member)] = member.observe(\.title, options: [.new]) { [weak self] _, _ in
                self?.scheduleRefresh()
            }
        }
        let selected = group?.selectedWindow ?? window
        let updated = windows.map {
            FloatingTabItem(id: ObjectIdentifier($0), title: $0.title, selected: $0 === selected)
        }
        if items != updated { items = updated }
        if case let .tab(identifier)? = keyboardSelection, !identifiers.contains(identifier) {
            self.keyboardSelection = selectedKeyboardTarget
        }
        didRefresh?()
    }
}
