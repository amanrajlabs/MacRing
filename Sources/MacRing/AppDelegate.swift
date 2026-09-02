import AppKit
import MacRingKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let holdMonitor = ModifierHoldMonitor()
    private var settings: SettingsWindowController?
    private var axMenuItem: NSMenuItem!
    private var axPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.grid.cross",
                                           accessibilityDescription: "MacRing")
        statusItem.menu = buildMenu()

        // A wheel already on screen (sticky via hotkey/menu, or pinned by a
        // click) is left alone: the hold combo must not reset its state.
        holdMonitor.onTriggerDown = {
            guard !RingPanelController.shared.isVisible else { return }
            RingPanelController.shared.show(sticky: false)
        }
        holdMonitor.onTriggerUp = {
            guard !RingPanelController.shared.isSticky else { return }
            RingPanelController.shared.activateHoveredOrHide()
        }
        HotkeyCenter.shared.onHotkey = { RingPanelController.shared.toggle(sticky: true) }

        applyConfig()
        NotificationCenter.default.addObserver(forName: ConfigStore.changedNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.applyConfig() }
        }

        if ConfigStore.shared.config.trigger.holdEnabled, !ModifierHoldMonitor.isTrusted {
            ModifierHoldMonitor.promptForTrust()
        }

        WelcomeWindowController.showIfFirstRun()
    }

    private func applyConfig() {
        let cfg = ConfigStore.shared.config
        holdMonitor.configure(names: cfg.trigger.holdModifiers, enabled: cfg.trigger.holdEnabled)
        if cfg.trigger.hotkeyEnabled {
            HotkeyCenter.shared.register(keyCode: cfg.trigger.hotkeyKeyCode,
                                         modifierNames: cfg.trigger.hotkeyModifiers)
        } else {
            HotkeyCenter.shared.unregister()
        }
        refreshMenuTitles()
        startAXPollingIfNeeded()
    }

    /// While the hold trigger is enabled but untrusted, watch for the user
    /// granting Accessibility so the monitor starts working without a relaunch.
    private func startAXPollingIfNeeded() {
        guard ConfigStore.shared.config.trigger.holdEnabled,
              !ModifierHoldMonitor.isTrusted else {
            axPollTimer?.invalidate()
            axPollTimer = nil
            return
        }
        guard axPollTimer == nil else { return }
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.checkAXTrust() }
        }
    }

    private func checkAXTrust() {
        guard ModifierHoldMonitor.isTrusted else { return }
        axPollTimer?.invalidate()
        axPollTimer = nil
        applyConfig() // reinstalls the hold monitor now that events will flow
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Open Ring", action: #selector(openRing), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Open Config File", action: #selector(openConfig), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        axMenuItem = menu.addItem(withTitle: "", action: #selector(grantAccessibility),
                                  keyEquivalent: "")
        axMenuItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacRing", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        return menu
    }

    private func refreshMenuTitles() {
        let trusted = ModifierHoldMonitor.isTrusted
        let combo = Modifiers.symbolString(ConfigStore.shared.config.trigger.holdModifiers)
        axMenuItem.title = trusted
            ? "Hold \(combo) to open the ring"
            : "Grant Accessibility (enables hold-\(combo) trigger)…"
        axMenuItem.isEnabled = !trusted
    }

    @objc private func openRing() { RingPanelController.shared.show(sticky: true) }

    @objc private func openSettings() {
        if settings == nil { settings = SettingsWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(ConfigStore.shared.configURL)
    }

    @objc private func reloadConfig() {
        ConfigStore.shared.reload()
        if let error = ConfigStore.shared.lastError {
            let alert = NSAlert()
            alert.messageText = "Config file has errors"
            alert.informativeText = "Kept the previous configuration.\n\n\(error)"
            alert.runModal()
        }
    }

    @objc private func grantAccessibility() {
        ModifierHoldMonitor.promptForTrust()
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
