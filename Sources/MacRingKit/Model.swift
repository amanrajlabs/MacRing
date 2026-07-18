import Foundation

/// One entry on the wheel. `symbol` overrides the default icon with an SF Symbol.
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
    /// v1 legacy nesting; decodable for migration, never rendered in v2.
    case submenu([RingItem])
    /// Extension point for future built-in mini-tools, routed to BuiltinRegistry.
    case builtin(String)

    public var kindName: String {
        switch self {
        case .app: "app"
        case .url: "url"
        case .file: "file"
        case .shell: "shell"
        case .shortcut: "shortcut"
        case .submenu: "submenu"
        case .builtin: "builtin"
        }
    }
}

// The config file is meant to be hand-editable, so items encode flat:
// {"title": "Safari", "type": "app", "value": "/Applications/Safari.app"}
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
        case "builtin": action = .builtin(try c.decode(String.self, forKey: .value))
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
        case .app(let v), .url(let v), .file(let v), .shell(let v),
             .shortcut(let v), .builtin(let v):
            try c.encode(v, forKey: .value)
        case .submenu(let children):
            try c.encode(children, forKey: .items)
        }
    }
}

/// A wedge on the inner ring; its items fan out on the outer ring.
public struct RingCategory: Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var items: [RingItem]

    public init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2",
                items: [RingItem] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.items = items
    }
}

extension RingCategory: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, symbol, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        items = try c.decodeIfPresent([RingItem].self, forKey: .items) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(items, forKey: .items)
    }
}

public struct AppearanceConfig: Codable, Equatable {
    public var ringRadius: Double
    public var iconSize: Double
    public var accentHex: String
    /// Opacity of the full-screen dim behind the wheel, 0...1.
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
    public var categories: [RingCategory]

    private enum CodingKeys: String, CodingKey {
        case version, trigger, appearance, categories, items
    }

    public init(version: Int = 2, trigger: TriggerConfig = TriggerConfig(),
                appearance: AppearanceConfig = AppearanceConfig(),
                categories: [RingCategory]) {
        self.version = version
        self.trigger = trigger
        self.appearance = appearance
        self.categories = categories
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trigger = try c.decodeIfPresent(TriggerConfig.self, forKey: .trigger) ?? TriggerConfig()
        appearance = try c.decodeIfPresent(AppearanceConfig.self, forKey: .appearance) ?? AppearanceConfig()
        if let cats = try c.decodeIfPresent([RingCategory].self, forKey: .categories) {
            categories = cats
        } else if let legacy = try c.decodeIfPresent([RingItem].self, forKey: .items) {
            categories = Self.migrate(legacyItems: legacy)
        } else {
            categories = []
        }
        version = 2
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(categories, forKey: .categories)
    }

    /// v1 → v2: root submenus become categories (nested submenus dropped);
    /// root leaves collect into a leading "General" category.
    static func migrate(legacyItems: [RingItem]) -> [RingCategory] {
        var categories: [RingCategory] = []
        var general: [RingItem] = []
        for item in legacyItems {
            if case .submenu(let children) = item.action {
                let leaves = children.filter {
                    if case .submenu = $0.action { false } else { true }
                }
                categories.append(RingCategory(id: item.id, name: item.title,
                                               symbol: item.symbol ?? "square.grid.2x2",
                                               items: leaves))
            } else {
                general.append(item)
            }
        }
        if !general.isEmpty {
            categories.insert(RingCategory(name: "General", symbol: "star", items: general), at: 0)
        }
        return categories
    }

    public static func defaultConfig() -> RingConfig {
        RingConfig(categories: [
            RingCategory(name: "AI Tools", symbol: "sparkles", items: [
                RingItem(title: "ChatGPT", action: .app("ChatGPT")),
                RingItem(title: "Claude", action: .app("Claude")),
                RingItem(title: "Perplexity", action: .url("https://www.perplexity.ai")),
            ]),
            RingCategory(name: "Photo & Video", symbol: "photo.on.rectangle", items: [
                RingItem(title: "Photos", action: .app("/System/Applications/Photos.app")),
                RingItem(title: "Preview", action: .app("/System/Applications/Preview.app")),
                RingItem(title: "QuickTime", action: .app("/System/Applications/QuickTime Player.app")),
                RingItem(title: "Screenshot", symbol: "camera.viewfinder", action: .shell("screencapture -ic")),
            ]),
            RingCategory(name: "Developer", symbol: "chevron.left.forwardslash.chevron.right", items: [
                RingItem(title: "Terminal", action: .app("/System/Applications/Utilities/Terminal.app")),
                RingItem(title: "VS Code", action: .app("Visual Studio Code")),
                RingItem(title: "GitHub", action: .url("https://github.com")),
            ]),
            RingCategory(name: "System & Utilities", symbol: "gearshape.2", items: [
                RingItem(title: "Settings", action: .app("/System/Applications/System Settings.app")),
                RingItem(title: "Activity Monitor", action: .app("/System/Applications/Utilities/Activity Monitor.app")),
                RingItem(title: "Disk Utility", action: .app("/System/Applications/Utilities/Disk Utility.app")),
                RingItem(title: "Sleep Display", symbol: "display", action: .shell("pmset displaysleepnow")),
            ]),
        ])
    }
}
