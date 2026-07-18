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
    private let model = WheelViewModel()
    private var timer: Timer?
    /// Sticky wheels (hotkey / menu) stay open until click, digit, Esc, or
    /// hotkey again. Non-sticky wheels (modifier hold) act on release.
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
        panel.contentView = NSHostingView(rootView: WheelView(model: model) { [weak self] in
            self?.handleClick()
        })
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onCancel = { [weak self] in self?.hide() }
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

        // y-down view coordinates, clamped so the whole wheel stays on screen.
        let probe = WheelLayout(center: .zero, appearanceRadius: config.appearance.ringRadius,
                                iconSize: config.appearance.iconSize)
        let margin = probe.outerOuterRadius + 20
        let x = min(max(mouse.x - frame.minX, margin), frame.width - margin)
        let y = min(max(frame.maxY - mouse.y, margin), frame.height - margin)
        model.reset(categories: config.categories, appearance: config.appearance,
                    center: CGPoint(x: x, y: y))

        panel.makeKeyAndOrderFront(nil)
        startTracking()
    }

    func hide() {
        stopTracking()
        panel.orderOut(nil)
    }

    /// Modifier-release path: run the hovered child; with just a category
    /// open, go sticky so the user can click or press a digit.
    func activateHoveredOrHide() {
        guard isVisible else { return }
        if let child = model.hoveredChild {
            hide()
            ActionRunner.run(child)
        } else if model.openCategoryIndex != nil {
            isSticky = true
        } else {
            hide()
        }
    }

    private func handleClick() {
        if let child = model.hoveredChild {
            hide()
            ActionRunner.run(child)
        } else if model.openCategoryIndex != nil {
            isSticky = true // clicked a category wedge (hover already opened it)
        } else {
            hide()
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Esc
            hide()
            return true
        }
        guard let char = event.charactersIgnoringModifiers?.first,
              let digit = char.wholeNumberValue, (1...9).contains(digit) else { return false }
        if let open = model.openCategory {
            guard open.items.indices.contains(digit - 1) else { return true }
            let item = open.items[digit - 1]
            hide()
            ActionRunner.run(item)
        } else {
            model.openCategory(at: digit - 1)
            isSticky = true
        }
        return true
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
        // flagsChanged event can't strand the wheel on screen.
        if !isSticky, !holdModifiers.isEmpty {
            let current = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
            if current != holdModifiers { activateHoveredOrHide() }
        }
    }
}
