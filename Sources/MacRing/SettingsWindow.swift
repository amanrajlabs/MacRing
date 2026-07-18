import AppKit
import MacRingKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "MacRing Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        self.init(window: window)
    }
}

// Editing conveniences over the flat action enum.
private extension RingItem {
    var valueString: String {
        get {
            switch action {
            case .app(let v), .url(let v), .file(let v), .shell(let v),
                 .shortcut(let v), .builtin(let v): v
            case .submenu: ""
            }
        }
        set {
            switch action {
            case .app: action = .app(newValue)
            case .url: action = .url(newValue)
            case .file: action = .file(newValue)
            case .shell: action = .shell(newValue)
            case .shortcut: action = .shortcut(newValue)
            case .builtin: action = .builtin(newValue)
            case .submenu: break
            }
        }
    }

    var kind: String {
        get { action.kindName }
        set {
            guard newValue != action.kindName else { return }
            let value = valueString
            switch newValue {
            case "app": action = .app(value)
            case "url": action = .url(value)
            case "file": action = .file(value)
            case "shell": action = .shell(value)
            case "shortcut": action = .shortcut(value)
            case "submenu": action = .submenu(children)
            default: break
            }
        }
    }

    var children: [RingItem] {
        get { if case .submenu(let c) = action { c } else { [] } }
        set { if case .submenu = action { action = .submenu(newValue) } }
    }

    var symbolText: String {
        get { symbol ?? "" }
        set { symbol = newValue.isEmpty ? nil : newValue }
    }
}

private struct HotkeyPreset: Identifiable {
    let label: String
    let keyCode: UInt32
    let mods: [String]
    var id: String { label }

    static let all = [
        HotkeyPreset(label: "⌃⌥Space", keyCode: 49, mods: ["control", "option"]),
        HotkeyPreset(label: "⌘⇧Space", keyCode: 49, mods: ["command", "shift"]),
        HotkeyPreset(label: "⌃⌥R", keyCode: 15, mods: ["control", "option"]),
        HotkeyPreset(label: "⌃⌥L", keyCode: 37, mods: ["control", "option"]),
    ]
}

struct SettingsView: View {
    @State private var config = ConfigStore.shared.config
    @State private var axTrusted = ModifierHoldMonitor.isTrusted
    @State private var saveWork: DispatchWorkItem?

    var body: some View {
        Form {
            triggerSection
            itemsSection
            appearanceSection
            footerSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 600, minHeight: 560)
        .onChange(of: config) { scheduleSave() }
        .onReceive(NotificationCenter.default.publisher(for: ConfigStore.changedNotification)) { _ in
            if ConfigStore.shared.config != config { config = ConfigStore.shared.config }
        }
        .onAppear { axTrusted = ModifierHoldMonitor.isTrusted }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = config
        let work = DispatchWorkItem { ConfigStore.shared.save(snapshot) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: Trigger

    private var triggerSection: some View {
        Section("Trigger") {
            Toggle("Hold modifiers to open the ring", isOn: $config.trigger.holdEnabled)
            if config.trigger.holdEnabled {
                HStack(spacing: 16) {
                    modifierToggle("⌃ control", "control")
                    modifierToggle("⌥ option", "option")
                    modifierToggle("⇧ shift", "shift")
                    modifierToggle("⌘ command", "command")
                }
                if config.trigger.holdModifiers.count < 2 {
                    Text("Pick at least two modifiers or the ring will pop up constantly.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !axTrusted {
                    HStack {
                        Text("Needs Accessibility permission.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Grant…") {
                            ModifierHoldMonitor.promptForTrust()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button("Re-check") { axTrusted = ModifierHoldMonitor.isTrusted }
                    }
                }
            }
            Toggle("Hotkey toggles the ring", isOn: $config.trigger.hotkeyEnabled)
            if config.trigger.hotkeyEnabled {
                Picker("Hotkey", selection: hotkeyBinding) {
                    ForEach(HotkeyPreset.all) { Text($0.label).tag($0.label) }
                    if currentPresetLabel == nil { Text("Custom").tag("Custom") }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func modifierToggle(_ label: String, _ name: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { config.trigger.holdModifiers.contains(name) },
            set: { on in
                var mods = config.trigger.holdModifiers.filter { $0 != name }
                if on { mods.append(name) }
                config.trigger.holdModifiers = mods
            }))
        .toggleStyle(.checkbox)
    }

    private var currentPresetLabel: String? {
        HotkeyPreset.all.first {
            $0.keyCode == config.trigger.hotkeyKeyCode
                && Set($0.mods) == Set(config.trigger.hotkeyModifiers)
        }?.label
    }

    private var hotkeyBinding: Binding<String> {
        Binding(
            get: { currentPresetLabel ?? "Custom" },
            set: { label in
                guard let preset = HotkeyPreset.all.first(where: { $0.label == label }) else { return }
                config.trigger.hotkeyKeyCode = preset.keyCode
                config.trigger.hotkeyModifiers = preset.mods
            })
    }

    // MARK: Items

    private var itemsSection: some View {
        Section("Categories") {
            ForEach(config.categories) { category in
                LabeledContent(category.name, value: "\(category.items.count) items")
            }
            Text("Category editing arrives with the wheel editor (Task 5). Until then, edit the config file directly.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            LabeledContent("Ring radius") {
                Slider(value: $config.appearance.ringRadius, in: 90...220) {
                    EmptyView()
                } minimumValueLabel: { Text("S") } maximumValueLabel: { Text("L") }
                .frame(width: 260)
            }
            LabeledContent("Icon size") {
                Slider(value: $config.appearance.iconSize, in: 32...72) {
                    EmptyView()
                } minimumValueLabel: { Text("S") } maximumValueLabel: { Text("L") }
                .frame(width: 260)
            }
            LabeledContent("Background dim") {
                Slider(value: $config.appearance.dimOpacity, in: 0...0.6)
                    .frame(width: 260)
            }
            LabeledContent("Accent color") {
                HStack {
                    Circle()
                        .fill(Color(hex: config.appearance.accentHex))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.4)))
                    TextField("#FF9F0A", text: $config.appearance.accentHex)
                        .frame(width: 100)
                }
            }
        }
    }

    // MARK: Footer

    private var footerSection: some View {
        Section {
            HStack {
                Button("Open Config File") {
                    NSWorkspace.shared.open(ConfigStore.shared.configURL)
                }
                Button("Reload From Disk") {
                    ConfigStore.shared.reload()
                    config = ConfigStore.shared.config
                }
                Spacer()
                Text("Changes save automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = ConfigStore.shared.lastError {
                Text("Config file error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

