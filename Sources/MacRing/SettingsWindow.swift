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
            case .app(let v), .url(let v), .file(let v), .shell(let v), .shortcut(let v): v
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
        Section("Ring Items") {
            ItemsEditor(items: $config.items, allowSubmenu: true)
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

private struct ItemsEditor: View {
    @Binding var items: [RingItem]
    let allowSubmenu: Bool

    private var kinds: [String] {
        allowSubmenu
            ? ["app", "url", "file", "shell", "shortcut", "submenu"]
            : ["app", "url", "file", "shell", "shortcut"]
    }

    var body: some View {
        ForEach($items, id: \.id) { $item in
            ItemRow(item: $item, kinds: kinds, allowSubmenu: allowSubmenu,
                    onDelete: { remove(item.id) },
                    onUp: { move(item.id, by: -1) },
                    onDown: { move(item.id, by: 1) })
        }
        HStack {
            Button("Add Item") {
                items.append(RingItem(title: "New Item", action: .app("")))
            }
            if allowSubmenu {
                Button("Add Submenu") {
                    items.append(RingItem(title: "New Submenu", action: .submenu([])))
                }
            }
            Spacer()
            Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }
}

private struct ItemRow: View {
    @Binding var item: RingItem
    let kinds: [String]
    let allowSubmenu: Bool
    let onDelete: () -> Void
    let onUp: () -> Void
    let onDown: () -> Void

    private var valuePlaceholder: String {
        switch item.kind {
        case "app": "Path, bundle id, or app name"
        case "url": "https://…"
        case "file": "Path (~ allowed)"
        case "shell": "Shell command (zsh)"
        case "shortcut": "Shortcut name"
        default: ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Title", text: $item.title)
                    .frame(width: 140)
                Picker("", selection: $item.kind) {
                    ForEach(kinds, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .frame(width: 100)
                if item.kind == "submenu" {
                    Text("\(item.children.count) children")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    TextField(valuePlaceholder, text: $item.valueString)
                }
                controls
            }
            HStack {
                TextField("SF Symbol override (optional)", text: $item.symbolText)
                    .font(.caption)
                    .frame(width: 220)
                Spacer()
            }
            if item.kind == "submenu", allowSubmenu {
                DisclosureGroup("Submenu items") {
                    ItemsEditor(items: $item.children, allowSubmenu: false)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button(action: onUp) { Image(systemName: "chevron.up") }
            Button(action: onDown) { Image(systemName: "chevron.down") }
            Button(action: onDelete) { Image(systemName: "trash") }
        }
        .buttonStyle(.borderless)
    }
}
