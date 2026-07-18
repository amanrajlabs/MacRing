import AppKit
import MacRingKit
import SwiftUI

/// Shown exactly once, on first launch: teaches the two triggers and where
/// Settings lives. Re-test with: defaults delete com.aman.MacRing didShowWelcome
@MainActor
final class WelcomeWindowController: NSWindowController {
    private static var retained: WelcomeWindowController?
    private static let defaultsKey = "didShowWelcome"

    static func showIfFirstRun() {
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let controller = WelcomeWindowController()
        retained = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 0),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Welcome to MacRing"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WelcomeView(close: {
            Self.retained?.close()
            Self.retained = nil
        }))
        window.center()
        self.init(window: window)
    }
}

private struct WelcomeView: View {
    var close: () -> Void

    private var holdCombo: String {
        Modifiers.symbolString(ConfigStore.shared.config.trigger.holdModifiers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Hold **\(holdCombo)** anywhere — the wheel opens under your cursor. Slide to a tool, release to launch it.")
            } icon: {
                Image(systemName: "circle.grid.cross")
            }
            Label {
                Text("Press **⌃⌥Space** for a wheel that stays open — click wedges or press 1–9. Esc closes.")
            } icon: {
                Image(systemName: "keyboard")
            }
            Label {
                Text("Customize categories, triggers, and looks from the menu bar icon → **Settings…**")
            } icon: {
                Image(systemName: "gearshape")
            }
            HStack {
                Spacer()
                Button("Try the Wheel") {
                    close()
                    RingPanelController.shared.show(sticky: true)
                }
                Button("Done") { close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
