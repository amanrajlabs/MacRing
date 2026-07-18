import Foundation

/// One entry on the ring. `symbol` overrides the default icon with an SF Symbol.
public struct RingItem: Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var symbol: String?
    public var action: RingAction

    public init(id: UUID = UUID(), title: String, symbol: String? = nil, action: RingAction) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.action = action
    }
}

public enum RingAction: Equatable {
    /// App path ("/Applications/Safari.app"), bundle id, or bare name ("Safari").
    case app(String)
    case url(String)
    /// File or folder path, "~" allowed.
    case file(String)
    /// Run with `zsh -lc`.
    case shell(String)
    /// macOS Shortcuts workflow name, run via `shortcuts run`.
    case shortcut(String)
    case submenu([RingItem])

    public var kindName: String {
        switch self {
        case .app: "app"
        case .url: "url"
        case .file: "file"
        case .shell: "shell"
        case .shortcut: "shortcut"
        case .submenu: "submenu"
        }
    }
}

// The config file is meant to be hand-editable, so items encode flat:
// {"title": "Safari", "type": "app", "value": "/Applications/Safari.app"}
// {"title": "Tools", "type": "submenu", "items": [...]}
extension RingItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, symbol, type, value, items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "app": action = .app(try c.decode(String.self, forKey: .value))
        case "url": action = .url(try c.decode(String.self, forKey: .value))
        case "file": action = .file(try c.decode(String.self, forKey: .value))
        case "shell": action = .shell(try c.decode(String.self, forKey: .value))
        case "shortcut": action = .shortcut(try c.decode(String.self, forKey: .value))
        case "submenu": action = .submenu(try c.decode([RingItem].self, forKey: .items))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown item type '\(type)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(symbol, forKey: .symbol)
        try c.encode(action.kindName, forKey: .type)
        switch action {
        case .app(let v), .url(let v), .file(let v), .shell(let v), .shortcut(let v):
            try c.encode(v, forKey: .value)
        case .submenu(let children):
            try c.encode(children, forKey: .items)
        }
    }
}

public struct AppearanceConfig: Codable, Equatable {
    public var ringRadius: Double
    public var iconSize: Double
    public var accentHex: String
    /// Opacity of the full-screen dim behind the ring, 0...1.
    public var dimOpacity: Double

    public init(ringRadius: Double = 130, iconSize: Double = 46,
                accentHex: String = "#FF9F0A", dimOpacity: Double = 0.25) {
        self.ringRadius = ringRadius
        self.iconSize = iconSize
        self.accentHex = accentHex
        self.dimOpacity = dimOpacity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppearanceConfig()
        ringRadius = try c.decodeIfPresent(Double.self, forKey: .ringRadius) ?? d.ringRadius
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? d.iconSize
        accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex) ?? d.accentHex
        dimOpacity = try c.decodeIfPresent(Double.self, forKey: .dimOpacity) ?? d.dimOpacity
    }
}

/// Modifier names used in config: "command", "option", "control", "shift".
public struct TriggerConfig: Codable, Equatable {
    public var holdEnabled: Bool
    public var holdModifiers: [String]
    public var hotkeyEnabled: Bool
    /// Carbon virtual key code (49 = Space).
    public var hotkeyKeyCode: UInt32
    public var hotkeyModifiers: [String]

    public init(holdEnabled: Bool = true, holdModifiers: [String] = ["option", "shift"],
                hotkeyEnabled: Bool = true, hotkeyKeyCode: UInt32 = 49,
                hotkeyModifiers: [String] = ["control", "option"]) {
        self.holdEnabled = holdEnabled
        self.holdModifiers = holdModifiers
        self.hotkeyEnabled = hotkeyEnabled
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TriggerConfig()
        holdEnabled = try c.decodeIfPresent(Bool.self, forKey: .holdEnabled) ?? d.holdEnabled
        holdModifiers = try c.decodeIfPresent([String].self, forKey: .holdModifiers) ?? d.holdModifiers
        hotkeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? d.hotkeyEnabled
        hotkeyKeyCode = try c.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? d.hotkeyKeyCode
        hotkeyModifiers = try c.decodeIfPresent([String].self, forKey: .hotkeyModifiers) ?? d.hotkeyModifiers
    }
}

public struct RingConfig: Codable, Equatable {
    public var version: Int
    public var trigger: TriggerConfig
    public var appearance: AppearanceConfig
    public var items: [RingItem]

    public init(version: Int = 1, trigger: TriggerConfig = TriggerConfig(),
                appearance: AppearanceConfig = AppearanceConfig(), items: [RingItem]) {
        self.version = version
        self.trigger = trigger
        self.appearance = appearance
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        trigger = try c.decodeIfPresent(TriggerConfig.self, forKey: .trigger) ?? TriggerConfig()
        appearance = try c.decodeIfPresent(AppearanceConfig.self, forKey: .appearance) ?? AppearanceConfig()
        items = try c.decodeIfPresent([RingItem].self, forKey: .items) ?? []
    }

    public static func defaultConfig() -> RingConfig {
        RingConfig(items: [
            RingItem(title: "Safari", action: .app("/Applications/Safari.app")),
            RingItem(title: "Notes", action: .app("/System/Applications/Notes.app")),
            RingItem(title: "Terminal", action: .app("/System/Applications/Utilities/Terminal.app")),
            RingItem(title: "Home", symbol: "folder", action: .file("~")),
            RingItem(title: "Screenshot", symbol: "camera.viewfinder", action: .shell("screencapture -ic")),
            RingItem(title: "GitHub", action: .url("https://github.com")),
            RingItem(title: "System", symbol: "gearshape.2", action: .submenu([
                RingItem(title: "Settings", action: .app("/System/Applications/System Settings.app")),
                RingItem(title: "Activity Monitor", action: .app("/System/Applications/Utilities/Activity Monitor.app")),
                RingItem(title: "Disk Utility", action: .app("/System/Applications/Utilities/Disk Utility.app")),
                RingItem(title: "Sleep Display", symbol: "display", action: .shell("pmset displaysleepnow")),
            ])),
        ])
    }
}
