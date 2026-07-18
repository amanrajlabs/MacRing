import AppKit
import MacRingKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
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
            default: break
            }
        }
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
    @State private var selectedCategoryID: UUID?

    var body: some View {
        TabView {
            ringTab.tabItem { Label("Ring", systemImage: "circle.grid.2x2") }
            Form { triggerSection }.formStyle(.grouped)
                .tabItem { Label("Trigger", systemImage: "keyboard") }
            Form { appearanceSection; footerSection }.formStyle(.grouped)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(minWidth: 700, minHeight: 560)
        .onChange(of: config) { scheduleSave() }
        .onReceive(NotificationCenter.default.publisher(for: ConfigStore.changedNotification)) { _ in
            if ConfigStore.shared.config != config { config = ConfigStore.shared.config }
        }
        .onAppear {
            axTrusted = ModifierHoldMonitor.isTrusted
            if selectedCategoryID == nil { selectedCategoryID = config.categories.first?.id }
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = config
        let work = DispatchWorkItem { ConfigStore.shared.save(snapshot) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: Ring tab

    private var ringTab: some View {
        HSplitView {
            categoryList
                .frame(minWidth: 200, maxWidth: 260)
            categoryDetail
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
    }

    private var categoryList: some View {
        VStack(spacing: 8) {
            List(selection: $selectedCategoryID) {
                ForEach(config.categories) { category in
                    Label {
                        Text(category.name)
                    } icon: {
                        Image(systemName: category.symbol)
                    }
                    .badge(category.items.count)
                    .tag(category.id)
                }
            }
            if config.categories.count > 10 {
                Text("More than 10 categories makes wedges cramped.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 6) {
                Button {
                    let new = RingCategory(name: "New Category")
                    config.categories.append(new)
                    selectedCategoryID = new.id
                } label: { Image(systemName: "plus") }
                Button {
                    guard let index = selectedIndex else { return }
                    config.categories.remove(at: index)
                    selectedCategoryID = config.categories.first?.id
                } label: { Image(systemName: "minus") }
                .disabled(selectedIndex == nil)
                Divider().frame(height: 14)
                Button { moveSelected(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(selectedIndex.map { $0 == 0 } ?? true)
                Button { moveSelected(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(selectedIndex.map { $0 == config.categories.count - 1 } ?? true)
                Spacer()
            }
            .buttonStyle(.borderless)
        }
    }

    private var selectedIndex: Int? {
        config.categories.firstIndex { $0.id == selectedCategoryID }
    }

    private func moveSelected(_ offset: Int) {
        guard let index = selectedIndex,
              config.categories.indices.contains(index + offset) else { return }
        config.categories.swapAt(index, index + offset)
    }

    @ViewBuilder
    private var categoryDetail: some View {
        if let index = selectedIndex {
            CategoryEditor(category: $config.categories[index])
                .id(config.categories[index].id)
                .padding(.leading, 12)
        } else {
            Text("Select or add a category")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Trigger (unchanged from v1)

    private var triggerSection: some View {
        Section("Trigger") {
            Toggle("Hold modifiers to open the wheel", isOn: $config.trigger.holdEnabled)
            if config.trigger.holdEnabled {
                HStack(spacing: 16) {
                    modifierToggle("⌃ control", "control")
                    modifierToggle("⌥ option", "option")
                    modifierToggle("⇧ shift", "shift")
                    modifierToggle("⌘ command", "command")
                }
                if config.trigger.holdModifiers.count < 2 {
                    Text("Pick at least two modifiers or the wheel will pop up constantly.")
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
            Toggle("Hotkey toggles the wheel", isOn: $config.trigger.hotkeyEnabled)
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

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            LabeledContent("Wheel size") {
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

// MARK: - Category editor

private struct CategoryEditor: View {
    @Binding var category: RingCategory
    @State private var showingAppPicker = false

    private let kinds = ["app", "url", "file", "shell", "shortcut"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Category name", text: $category.name)
                    .font(.headline)
                    .frame(width: 200)
                TextField("SF Symbol", text: $category.symbol)
                    .frame(width: 150)
                Image(systemName: category.symbol.isEmpty ? "questionmark" : category.symbol)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach($category.items, id: \.id) { $item in
                        ItemRow(item: $item, kinds: kinds,
                                onDelete: { category.items.removeAll { $0.id == item.id } },
                                onUp: { move(item.id, by: -1) },
                                onDown: { move(item.id, by: 1) })
                    }
                }
            }
            HStack {
                Button("Add App…") { showingAppPicker = true }
                Menu("Add Custom") {
                    Button("URL") { add(.url("https://")) }
                    Button("File / Folder") { add(.file("~/")) }
                    Button("Shell Command") { add(.shell("")) }
                    Button("Shortcut") { add(.shortcut("")) }
                }
                .frame(width: 120)
                Spacer()
                Text("\(category.items.count) item\(category.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet { app in
                category.items.append(RingItem(title: app.name, action: .app(app.path)))
            }
        }
    }

    private func add(_ action: RingAction) {
        category.items.append(RingItem(title: "New Item", action: action))
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = category.items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard category.items.indices.contains(target) else { return }
        category.items.swapAt(index, target)
    }
}

private struct ItemRow: View {
    @Binding var item: RingItem
    let kinds: [String]
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
        HStack(spacing: 8) {
            TextField("Title", text: $item.title)
                .frame(width: 120)
            Picker("", selection: $item.kind) {
                ForEach(kinds, id: \.self) { Text($0) }
            }
            .labelsHidden()
            .frame(width: 90)
            TextField(valuePlaceholder, text: $item.valueString)
            TextField("Symbol", text: $item.symbolText)
                .frame(width: 90)
            HStack(spacing: 4) {
                Button(action: onUp) { Image(systemName: "chevron.up") }
                Button(action: onDown) { Image(systemName: "chevron.down") }
                Button(action: onDelete) { Image(systemName: "trash") }
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - App picker

private struct AppPickerSheet: View {
    let onPick: (InstalledApp) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var apps: [InstalledApp] = []

    private var filtered: [InstalledApp] {
        query.isEmpty ? apps
            : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            List(filtered) { app in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 22, height: 22)
                    Text(app.name)
                    Spacer()
                    Text(app.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onPick(app)
                    dismiss()
                }
            }
            HStack {
                Text("Click an app to add it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(10)
        }
        .frame(width: 480, height: 440)
        .onAppear { apps = AppScanner.scan() }
    }
}
