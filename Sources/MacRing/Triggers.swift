import AppKit
import Carbon.HIToolbox
import MacRingKit

/// Watches `flagsChanged` globally: holding exactly the configured modifier
/// set opens the ring (after a short delay so ordinary shortcut chords don't
/// flash it); releasing them activates the hovered item.
/// The global monitor needs Accessibility trust.
@MainActor
final class ModifierHoldMonitor {
    var onTriggerDown: (() -> Void)?
    var onTriggerUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var required: NSEvent.ModifierFlags = []
    private var isDown = false
    private var pendingShow: DispatchWorkItem?

    func configure(names: [String], enabled: Bool) {
        stop()
        required = Modifiers.nsFlags(names)
        guard enabled, !required.isEmpty else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async { self?.handle(event.modifierFlags) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event.modifierFlags)
            return event
        }
    }

    private func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        pendingShow?.cancel()
        pendingShow = nil
        isDown = false
    }

    private func handle(_ flags: NSEvent.ModifierFlags) {
        let current = flags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])
        let matches = current == required
        if matches, !isDown {
            isDown = true
            let work = DispatchWorkItem { [weak self] in
                self?.pendingShow = nil
                self?.onTriggerDown?()
            }
            pendingShow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        } else if !matches, isDown {
            isDown = false
            if let pendingShow {
                // Released before the delay: it was a normal shortcut chord.
                pendingShow.cancel()
                self.pendingShow = nil
            } else {
                onTriggerUp?()
            }
        }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

/// Carbon global hotkey (works without Accessibility) that toggles the ring.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register(keyCode: UInt32, modifierNames: [String]) {
        unregister()
        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D52_4E47) /* 'MRNG' */, id: 1)
        let status = RegisterEventHotKey(keyCode, Modifiers.carbonFlags(modifierNames),
                                         hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("MacRing: RegisterEventHotKey failed (\(status))")
            hotKeyRef = nil
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { center.onHotkey?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
}
