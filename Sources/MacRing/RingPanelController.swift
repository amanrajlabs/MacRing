import AppKit
import MacRingKit
import SwiftUI

/// Borderless transparent panel that can take key focus without activating
/// the app, so Esc and digit keys work over whatever the user was doing.
final class RingPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class RingPanelController {
    static let shared = RingPanelController()

    private let panel: RingPanel
    private let model = RingViewModel()
    private var timer: Timer?
    /// Sticky rings (hotkey / menu) stay open until click, digit, Esc, or
    /// hotkey again. Non-sticky rings (modifier hold) act on release.
    private(set) var isSticky = false
    private var holdModifiers: NSEvent.ModifierFlags = []

    var isVisible: Bool { panel.isVisible }

    private init() {
        panel = RingPanel(contentRect: .zero,
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: RingView(model: model) { [weak self] in
            self?.handleClick()
        })
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if !self.model.pop() { self.hide() }
        }
    }

    func toggle(sticky: Bool) {
        if isVisible { hide() } else { show(sticky: sticky) }
    }

    func show(sticky: Bool) {
        let config = ConfigStore.shared.config
        isSticky = sticky
        holdModifiers = Modifiers.nsFlags(config.trigger.holdModifiers)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame
        panel.setFrame(frame, display: false)

        // y-down view coordinates, clamped so the whole ring stays on screen.
        let margin = config.appearance.ringRadius + config.appearance.iconSize + 30
        let x = min(max(mouse.x - frame.minX, margin), frame.width - margin)
        let y = min(max(frame.maxY - mouse.y, margin), frame.height - margin)
        model.reset(items: config.items, appearance: config.appearance,
                    center: CGPoint(x: x, y: y))

        panel.makeKeyAndOrderFront(nil)
        startTracking()
    }

    func hide() {
        stopTracking()
        panel.orderOut(nil)
    }

    /// Modifier-release path: run what's hovered, drill into a hovered
    /// submenu (ring then turns sticky), or just close.
    func activateHoveredOrHide() {
        guard isVisible else { return }
        guard let item = model.hoveredItem else { return hide() }
        activate(item)
    }

    private func activate(_ item: RingItem) {
        if case .submenu(let children) = item.action {
            model.push(children)
            isSticky = true
            return
        }
        hide()
        ActionRunner.run(item)
    }

    private func handleClick() {
        if let item = model.hoveredItem {
            activate(item)
        } else if !model.pop() {
            hide()
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Esc
            if !model.pop() { hide() }
            return true
        }
        if let char = event.charactersIgnoringModifiers?.first,
           let digit = char.wholeNumberValue, (1...9).contains(digit),
           model.currentItems.indices.contains(digit - 1) {
            model.hover(index: digit - 1)
            activate(model.currentItems[digit - 1])
            return true
        }
        return false
    }

    private func startTracking() {
        stopTracking()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
        t.tolerance = 0.005
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isVisible else { return stopTracking() }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        model.update(cursor: CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y))

        // Failsafe release detection for the hold trigger: NSEvent's class
        // property reads hardware state and needs no permissions, so a missed
        // flagsChanged event can't strand the ring on screen.
        if !isSticky, !holdModifiers.isEmpty {
            let current = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
            if current != holdModifiers { activateHoveredOrHide() }
        }
    }
}
