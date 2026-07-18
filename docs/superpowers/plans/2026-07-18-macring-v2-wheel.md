# MacRing v2 Segmented Category Wheel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace MacRing's floating-icon ring with an Orbs-style segmented two-ring wheel: categories as wedges on an inner ring, hovered category's apps fanning out as wedges on an outer arc, plus a category-based Settings editor with an installed-app picker.

**Architecture:** Pure math and models live in `MacRingKit` (checked by the `MacRingChecks` executable); rendering is SwiftUI wedge shapes inside the existing borderless `RingPanel`; triggers, config store, and bundling are already built and unchanged. Spec: `docs/superpowers/specs/2026-07-18-macring-v2-wheel-design.md`.

**Tech Stack:** Swift 6 toolchain in **language mode v5** (pinned in Package.swift), SwiftPM, AppKit + SwiftUI, macOS 14+.

## Global Constraints

- CLT-only machine: **no Xcode, no XCTest**. Tests are plain assertions in `Sources/MacRingChecks/main.swift`, run with `swift run MacRingChecks` (exits 1 on failure).
- Build app bundle with `./scripts/bundle.sh` → `dist/MacRing.app`. Relaunch: `pkill -x MacRing || true; open dist/MacRing.app`.
- Keep `swift build` green at the end of every task.
- Coordinates: y-down view space; angles in radians increasing clockwise; index 0 centered at top (−π/2). Never change this convention.
- Config JSON must stay hand-editable; decoding must default missing fields (existing pattern: `decodeIfPresent ?? default`).
- All UI classes `@MainActor`. Follow existing code style (4-space indent, `// MARK:` sections).
- Work on branch `feature/v2-wheel` (create from current default branch in Task 1, Step 1).
- Do not touch: `Triggers.swift`, `ConfigStore.swift`, `AppDelegate.swift` (except where a task explicitly says so), `scripts/`, `Resources/`.

---

### Task 1: Model v2 — categories, migration, builtin extension point

**Files:**
- Modify: `Sources/MacRingKit/Model.swift` (full replacement below)
- Create: `Sources/MacRingKit/BuiltinRegistry.swift`
- Modify: `Sources/MacRingKit/ActionRunner.swift` (one case added)
- Modify: `Sources/MacRingChecks/main.swift` (replace the "Model round-trip" section)
- Modify: `Sources/MacRing/RingPanelController.swift` (one line: temporary shim)
- Modify: `Sources/MacRing/SettingsWindow.swift` (items section → read-only placeholder)

**Interfaces:**
- Consumes: existing `RingItem`, `RingAction`, `RingConfig`, `TriggerConfig`, `AppearanceConfig`.
- Produces (later tasks rely on these exact names):
  - `public struct RingCategory: Identifiable, Equatable, Codable { var id: UUID; var name: String; var symbol: String; var items: [RingItem] }`
  - `RingConfig.categories: [RingCategory]`, `RingConfig.version == 2`
  - `RingConfig.legacyItems: [RingItem]` (compatibility shim, removed in Task 4)
  - `RingAction.builtin(String)`
  - `@MainActor public final class BuiltinRegistry { static let shared; func register(id: String, handler: @escaping () -> Void); func run(_ id: String) }`

- [ ] **Step 1: Create branch**

```bash
cd /Users/aman/Desktop/MyStuff/Hustle/PublicProjects/GitHub/MacRing
git checkout -b feature/v2-wheel
```

- [ ] **Step 2: Write the failing checks**

In `Sources/MacRingChecks/main.swift`, delete everything between `// MARK: Model round-trip` and `// MARK: Geometry` (the three `do{}` blocks) and insert:

```swift
// MARK: Model round-trip (v2)

do {
    let original = RingConfig.defaultConfig()
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(RingConfig.self, from: data)
    check(decoded == original, "default config encodes and decodes losslessly")
    check(original.version == 2 && original.categories.count == 4,
          "default config is v2 with four categories")
} catch {
    check(false, "default config round-trip threw: \(error)")
}

// v1 file (root items + submenu) migrates to categories.
do {
    let v1 = """
    {"version": 1, "items": [
      {"title": "Safari", "type": "app", "value": "Safari"},
      {"title": "Tools", "type": "submenu", "symbol": "wrench", "items": [
        {"title": "Ping", "type": "shell", "value": "ping -c1 1.1.1.1"},
        {"title": "Nested", "type": "submenu", "items": [
          {"title": "Deep", "type": "url", "value": "https://x.com"}]}
      ]}
    ]}
    """
    let cfg = try JSONDecoder().decode(RingConfig.self, from: Data(v1.utf8))
    check(cfg.version == 2, "v1 config migrates to version 2")
    check(cfg.categories.count == 2, "migration yields General + Tools")
    check(cfg.categories[0].name == "General" && cfg.categories[0].items.count == 1,
          "root leaves land in a leading General category")
    check(cfg.categories[1].symbol == "wrench" && cfg.categories[1].items.count == 1,
          "submenu becomes category; nested submenus are dropped")
} catch {
    check(false, "v1 migration threw: \(error)")
}

do {
    let bad = Data(#"{"categories": [{"name": "X", "items": [{"title": "Y", "type": "warp", "value": "z"}]}]}"#.utf8)
    check((try? JSONDecoder().decode(RingConfig.self, from: bad)) == nil,
          "unknown item type is rejected")
}

check(RingAction.builtin("timer").kindName == "builtin", "builtin action kind name")
```

- [ ] **Step 3: Run checks to verify they fail**

Run: `swift run MacRingChecks`
Expected: compile errors (`RingConfig` has no member `categories`, no `defaultConfig` with categories, no `builtin` case). Compile failure counts as the failing state.

- [ ] **Step 4: Replace `Sources/MacRingKit/Model.swift` with:**

```swift
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

    /// TEMPORARY shim so the v1 ring UI keeps working until Task 4 replaces it.
    /// Task 4 deletes this property.
    public var legacyItems: [RingItem] {
        categories.map { RingItem(id: $0.id, title: $0.name, symbol: $0.symbol,
                                  action: .submenu($0.items)) }
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
```

- [ ] **Step 5: Create `Sources/MacRingKit/BuiltinRegistry.swift`:**

```swift
import AppKit

/// Future home of built-in mini-tools (timer, color picker, …). v2 ships it
/// empty; `builtin` actions with no registered handler log and beep.
@MainActor
public final class BuiltinRegistry {
    public static let shared = BuiltinRegistry()
    private var handlers: [String: () -> Void] = [:]

    public func register(id: String, handler: @escaping () -> Void) {
        handlers[id] = handler
    }

    public func run(_ id: String) {
        guard let handler = handlers[id] else {
            NSLog("MacRing: no builtin registered for '\(id)'")
            NSSound.beep()
            return
        }
        handler()
    }
}
```

- [ ] **Step 6: In `Sources/MacRingKit/ActionRunner.swift`, replace**

```swift
        case .submenu:
            break // handled by the ring UI, never executed directly
```

with:

```swift
        case .submenu:
            break // legacy v1 nesting; handled by UI, never executed directly
        case .builtin(let id):
            BuiltinRegistry.shared.run(id)
```

- [ ] **Step 7: Point the v1 UI at the shim (temporary)**

In `Sources/MacRing/RingPanelController.swift`, inside `show(sticky:)`, replace

```swift
        model.reset(items: config.items, appearance: config.appearance,
                    center: CGPoint(x: x, y: y))
```

with:

```swift
        model.reset(items: config.legacyItems, appearance: config.appearance,
                    center: CGPoint(x: x, y: y))
```

In `Sources/MacRing/SettingsWindow.swift`, replace the `itemsSection` computed property with this read-only placeholder (the full category editor arrives in Task 5; delete the now-unused `ItemsEditor`, `ItemRow`, and the `private extension RingItem` block in this file if the compiler flags them as unused — otherwise leaving them is harmless):

```swift
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
```

Note: `ItemsEditor`/`ItemRow` reference `$config.items` which no longer exists — **delete both structs and the `private extension RingItem` helpers** in `SettingsWindow.swift` now; Task 5 reintroduces what it needs.

- [ ] **Step 8: Run checks to verify they pass**

Run: `swift build && swift run MacRingChecks`
Expected: `Build complete!`, all checks `ok`, final line `All checks passed.`

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(model): v2 category model, v1 migration, builtin extension point"
```

---

### Task 2: WheelGeometry — bands, wedges, child arcs

**Files:**
- Create: `Sources/MacRingKit/WheelGeometry.swift`
- Modify: `Sources/MacRingChecks/main.swift` (append a section before the final `print`)
- Note: leave `RingGeometry.swift` in place until Task 4 (v1 UI still uses it).

**Interfaces:**
- Produces (Task 4 relies on these exact signatures):
  - `public struct WheelLayout { init(center: CGPoint, appearanceRadius: CGFloat, iconSize: CGFloat); var center: CGPoint; var holeRadius, innerOuterRadius, gap, outerBandWidth, outerInnerRadius, outerOuterRadius, innerMidRadius, outerMidRadius: CGFloat }`
  - `public enum WheelRegion { case hub, innerBand, gap, outerBand, outside }`
  - `WheelGeometry.region(of: CGPoint, in: WheelLayout) -> WheelRegion`
  - `WheelGeometry.angle(of: CGPoint, around: CGPoint) -> CGFloat`
  - `WheelGeometry.categoryIndex(atAngle: CGFloat, count: Int) -> Int?`
  - `WheelGeometry.categoryMidAngle(_ index: Int, count: Int) -> CGFloat`
  - `WheelGeometry.Arc { start, step: CGFloat; count: Int; end: CGFloat; func midAngle(Int) -> CGFloat }`
  - `WheelGeometry.childArc(categoryIndex: Int, categoryCount: Int, childCount: Int, layout: WheelLayout, arcLength: CGFloat = 78) -> Arc`
  - `WheelGeometry.childIndex(atAngle: CGFloat, arc: Arc) -> Int?`

- [ ] **Step 1: Write the failing checks**

Append to `Sources/MacRingChecks/main.swift`, immediately before the final `print(failures == 0 ...)` line:

```swift
// MARK: Wheel geometry

let layout = WheelLayout(center: .zero, appearanceRadius: 100, iconSize: 46)
check(WheelGeometry.region(of: CGPoint(x: 20, y: 0), in: layout) == .hub, "hub region")
check(WheelGeometry.region(of: CGPoint(x: 70, y: 0), in: layout) == .innerBand, "inner band region")
check(WheelGeometry.region(of: CGPoint(x: 102, y: 0), in: layout) == .gap, "gap region")
check(WheelGeometry.region(of: CGPoint(x: 140, y: 0), in: layout) == .outerBand, "outer band region")
check(WheelGeometry.region(of: CGPoint(x: 500, y: 0), in: layout) == .outside, "outside region")

check(WheelGeometry.categoryIndex(atAngle: -.pi / 2, count: 4) == 0, "top angle is category 0")
check(WheelGeometry.categoryIndex(atAngle: 0, count: 4) == 1, "right angle is category 1")
check(WheelGeometry.categoryIndex(atAngle: .pi, count: 4) == 3, "left angle is category 3")
check(WheelGeometry.categoryIndex(atAngle: 0, count: 0) == nil, "no categories, no index")

let arc = WheelGeometry.childArc(categoryIndex: 1, categoryCount: 4, childCount: 3, layout: layout)
check(abs(arc.midAngle(1) - 0) < 0.001, "child arc centers on its category angle")
let bigArc = WheelGeometry.childArc(categoryIndex: 0, categoryCount: 4, childCount: 40, layout: layout)
check(bigArc.step * 40 <= 2 * .pi + 0.001, "40 children clamp to a full circle")
check(WheelGeometry.childIndex(atAngle: arc.midAngle(2), arc: arc) == 2, "mid angle hits its wedge")
check(WheelGeometry.childIndex(atAngle: arc.end + 0.3, arc: arc) == nil, "outside the arc hovers nothing")
check(WheelGeometry.childIndex(atAngle: arc.midAngle(0), arc: WheelGeometry.Arc(start: 0, step: 0.5, count: 0)) == nil,
      "empty arc hovers nothing")
```

- [ ] **Step 2: Run to verify failure**

Run: `swift run MacRingChecks`
Expected: compile error `cannot find 'WheelLayout' in scope`.

- [ ] **Step 3: Create `Sources/MacRingKit/WheelGeometry.swift`:**

```swift
import CoreGraphics
import Foundation

/// Radial layout of the two-band wheel, derived from appearance settings.
/// All values in points; y-down coordinates.
public struct WheelLayout: Equatable {
    public var center: CGPoint
    public var holeRadius: CGFloat
    public var innerOuterRadius: CGFloat
    public var gap: CGFloat
    public var outerBandWidth: CGFloat

    public init(center: CGPoint, appearanceRadius: CGFloat, iconSize: CGFloat) {
        self.center = center
        holeRadius = appearanceRadius * 0.40
        innerOuterRadius = appearanceRadius
        gap = 5
        outerBandWidth = max(iconSize + 34, appearanceRadius * 0.52)
    }

    public var outerInnerRadius: CGFloat { innerOuterRadius + gap }
    public var outerOuterRadius: CGFloat { outerInnerRadius + outerBandWidth }
    public var innerMidRadius: CGFloat { (holeRadius + innerOuterRadius) / 2 }
    public var outerMidRadius: CGFloat { (outerInnerRadius + outerOuterRadius) / 2 }
}

public enum WheelRegion: Equatable {
    case hub, innerBand, gap, outerBand, outside
}

/// Pure wheel math. Angles are radians, y-down, increasing clockwise;
/// category 0 is centered at the top (-π/2). Category wedges divide the full
/// circle equally; child wedges fan out on an arc centered on their category.
public enum WheelGeometry {
    public static func region(of point: CGPoint, in layout: WheelLayout) -> WheelRegion {
        let d = hypot(point.x - layout.center.x, point.y - layout.center.y)
        if d < layout.holeRadius { return .hub }
        if d < layout.innerOuterRadius { return .innerBand }
        if d < layout.outerInnerRadius { return .gap }
        if d < layout.outerOuterRadius { return .outerBand }
        return .outside
    }

    public static func angle(of point: CGPoint, around center: CGPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x)
    }

    public static func categoryMidAngle(_ index: Int, count: Int) -> CGFloat {
        -.pi / 2 + 2 * .pi * CGFloat(index) / CGFloat(max(count, 1))
    }

    public static func categoryIndex(atAngle theta: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let step = 2 * .pi / CGFloat(count)
        var rel = (theta + .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
        if rel < 0 { rel += 2 * .pi }
        return Int((rel / step).rounded()) % count
    }

    public struct Arc: Equatable {
        public var start: CGFloat
        public var step: CGFloat
        public var count: Int

        public init(start: CGFloat, step: CGFloat, count: Int) {
            self.start = start
            self.step = step
            self.count = count
        }

        public var end: CGFloat { start + step * CGFloat(count) }

        public func midAngle(_ index: Int) -> CGFloat {
            start + step * (CGFloat(index) + 0.5)
        }
    }

    /// Each child wedge subtends ~`arcLength` points at the outer band's mid
    /// radius, capped so the whole arc never exceeds a full circle.
    public static func childArc(categoryIndex: Int, categoryCount: Int, childCount: Int,
                                layout: WheelLayout, arcLength: CGFloat = 78) -> Arc {
        let per = min(arcLength / layout.outerMidRadius,
                      2 * .pi / CGFloat(max(childCount, 1)))
        let mid = categoryMidAngle(categoryIndex, count: categoryCount)
        return Arc(start: mid - per * CGFloat(childCount) / 2, step: per, count: childCount)
    }

    public static func childIndex(atAngle theta: CGFloat, arc: Arc) -> Int? {
        guard arc.count > 0, arc.step > 0 else { return nil }
        var rel = (theta - arc.start).truncatingRemainder(dividingBy: 2 * .pi)
        if rel < 0 { rel += 2 * .pi }
        guard rel < arc.step * CGFloat(arc.count) else { return nil }
        return min(Int(rel / arc.step), arc.count - 1)
    }
}
```

- [ ] **Step 4: Run checks to verify pass**

Run: `swift run MacRingChecks`
Expected: all checks `ok`, `All checks passed.`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(kit): wheel band/wedge/arc geometry with checks"
```

---

### Task 3: AppScanner — installed application inventory

**Files:**
- Create: `Sources/MacRingKit/AppScanner.swift`
- Modify: `Sources/MacRingChecks/main.swift` (append before final `print`)

**Interfaces:**
- Produces (Task 5 relies on):
  - `public struct InstalledApp: Identifiable, Equatable, Sendable { let name: String; let path: String; var id: String }`
  - `AppScanner.scan() -> [InstalledApp]` (sorted by name, deduped by path)

- [ ] **Step 1: Write the failing checks** (append before final `print`):

```swift
// MARK: App scanner

let apps = AppScanner.scan()
check(!apps.isEmpty, "scanner finds applications")
check(apps.contains { $0.name == "Notes" }, "scanner finds system apps")
check(Set(apps.map(\.path)).count == apps.count, "scanner paths are unique")
check(apps == apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
      "scanner output is name-sorted")
```

- [ ] **Step 2: Run to verify failure**

Run: `swift run MacRingChecks`
Expected: compile error `cannot find 'AppScanner' in scope`.

- [ ] **Step 3: Create `Sources/MacRingKit/AppScanner.swift`:**

```swift
import Foundation

public struct InstalledApp: Identifiable, Equatable, Sendable {
    public let name: String
    public let path: String
    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// Shallow scan of the standard application folders (one subfolder level in
/// /Applications for vendor directories). Cheap enough to run on demand.
public enum AppScanner {
    public static func scan() -> [InstalledApp] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var found: [String: InstalledApp] = [:]
        collect(in: "/Applications", depth: 1, into: &found)
        collect(in: "/System/Applications", depth: 0, into: &found)
        collect(in: "/System/Applications/Utilities", depth: 0, into: &found)
        collect(in: home + "/Applications", depth: 0, into: &found)
        return found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func collect(in dir: String, depth: Int,
                                into found: inout [String: InstalledApp]) {
        let fm = FileManager.default
        for entry in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
            let path = dir + "/" + entry
            if entry.hasSuffix(".app") {
                found[path] = InstalledApp(name: String(entry.dropLast(4)), path: path)
            } else if depth > 0, !entry.hasPrefix(".") {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    collect(in: path, depth: depth - 1, into: &found)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run checks to verify pass**

Run: `swift run MacRingChecks`
Expected: all `ok`, `All checks passed.`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(kit): installed-app scanner for the settings picker"
```

---

### Task 4: Wheel UI — wedge rendering, two-band hover, activation

**Files:**
- Create: `Sources/MacRing/WheelViewModel.swift`
- Create: `Sources/MacRing/WheelView.swift`
- Delete: `Sources/MacRing/RingView.swift`, `Sources/MacRing/RingViewModel.swift`
- Modify: `Sources/MacRing/RingPanelController.swift` (full replacement below)
- Modify: `Sources/MacRingKit/Model.swift` (delete the `legacyItems` property)
- Delete file: `Sources/MacRingKit/RingGeometry.swift`; in `Sources/MacRingChecks/main.swift` delete the `// MARK: Geometry` section (the v1 `RingGeometry` checks — keep the `// MARK: Wheel geometry` section).

**Interfaces:**
- Consumes: `WheelLayout`, `WheelGeometry`, `WheelRegion`, `RingCategory`, `RingConfig.categories`, `ActionRunner.run(_:)`, existing `RingPanel`, `ConfigStore.shared`, `Modifiers.nsFlags`.
- Produces: `WheelViewModel` (`reset(categories:appearance:center:)`, `update(cursor:)`, `openCategoryIndex: Int?`, `hoveredChildIndex: Int?`, `openCategory: RingCategory?`, `hoveredChild: RingItem?`, `childArc: WheelGeometry.Arc?`, `layout: WheelLayout`, `openCategory(at index: Int)`), `WheelView(model:onTap:)`. `RingPanelController.shared` keeps its public surface: `show(sticky:)`, `hide()`, `toggle(sticky:)`, `activateHoveredOrHide()`, `isVisible`.
- `IconProvider` and `Color(hex:)` move into `WheelView.swift` unchanged; `IconProvider.fallbackSymbol` gains a `builtin` case returning `"puzzlepiece.extension"`.

- [ ] **Step 1: Create `Sources/MacRing/WheelViewModel.swift`:**

```swift
import AppKit
import MacRingKit
import SwiftUI

/// State for one wheel session. The open category owns the fanned outer arc;
/// hover state is derived from the cursor's radial region and angle.
/// Coordinates are y-down view coordinates of the panel.
@MainActor
final class WheelViewModel: ObservableObject {
    @Published var categories: [RingCategory] = []
    @Published var openCategoryIndex: Int?
    @Published var hoveredChildIndex: Int?
    @Published var appearance = AppearanceConfig()
    @Published var center = CGPoint.zero

    var layout: WheelLayout {
        WheelLayout(center: center, appearanceRadius: appearance.ringRadius,
                    iconSize: appearance.iconSize)
    }

    var openCategory: RingCategory? {
        guard let openCategoryIndex, categories.indices.contains(openCategoryIndex) else { return nil }
        return categories[openCategoryIndex]
    }

    var hoveredChild: RingItem? {
        guard let openCategory, let hoveredChildIndex,
              openCategory.items.indices.contains(hoveredChildIndex) else { return nil }
        return openCategory.items[hoveredChildIndex]
    }

    var childArc: WheelGeometry.Arc? {
        guard let openCategoryIndex, categories.indices.contains(openCategoryIndex) else { return nil }
        return WheelGeometry.childArc(categoryIndex: openCategoryIndex,
                                      categoryCount: categories.count,
                                      childCount: categories[openCategoryIndex].items.count,
                                      layout: layout)
    }

    func reset(categories: [RingCategory], appearance: AppearanceConfig, center: CGPoint) {
        self.categories = categories
        self.appearance = appearance
        self.center = center
        openCategoryIndex = nil
        hoveredChildIndex = nil
    }

    func update(cursor: CGPoint) {
        switch WheelGeometry.region(of: cursor, in: layout) {
        case .innerBand:
            let theta = WheelGeometry.angle(of: cursor, around: center)
            if let idx = WheelGeometry.categoryIndex(atAngle: theta, count: categories.count),
               idx != openCategoryIndex {
                openCategoryIndex = idx
            }
            hoveredChildIndex = nil
        case .outerBand, .outside:
            // Outside stays angular so a fast flick past the band still selects.
            guard let arc = childArc else { return }
            hoveredChildIndex = WheelGeometry.childIndex(
                atAngle: WheelGeometry.angle(of: cursor, around: center), arc: arc)
        case .hub, .gap:
            hoveredChildIndex = nil
        }
    }

    func openCategory(at index: Int) {
        guard categories.indices.contains(index) else { return }
        openCategoryIndex = index
        hoveredChildIndex = nil
    }
}
```

- [ ] **Step 2: Create `Sources/MacRing/WheelView.swift`:**

```swift
import AppKit
import MacRingKit
import SwiftUI

extension Color {
    /// "#RRGGBB" or "RRGGBB"; falls back to orange on garbage.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = .orange
            return
        }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

@MainActor
enum IconProvider {
    /// Real app/file icons when available; otherwise nil and the view falls
    /// back to an SF Symbol.
    static func nsImage(for item: RingItem) -> NSImage? {
        if item.symbol != nil { return nil }
        switch item.action {
        case .app(let value):
            guard let url = ActionRunner.resolveAppURL(value) else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        case .file(let value):
            let path = (value as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return NSWorkspace.shared.icon(forFile: path)
        default:
            return nil
        }
    }

    static func fallbackSymbol(for item: RingItem) -> String {
        if let symbol = item.symbol { return symbol }
        switch item.action {
        case .app: return "app.dashed"
        case .url: return "globe"
        case .file: return "folder"
        case .shell: return "terminal"
        case .shortcut: return "wand.and.stars"
        case .submenu: return "square.grid.3x3"
        case .builtin: return "puzzlepiece.extension"
        }
    }
}

/// Donut sector between two angles (radians, y-down, clockwise-increasing),
/// drawn around the frame's center.
struct WedgeShape: Shape {
    var startAngle: CGFloat
    var endAngle: CGFloat
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: outerRadius,
                 startAngle: .radians(startAngle), endAngle: .radians(endAngle),
                 clockwise: false)
        p.addArc(center: c, radius: innerRadius,
                 startAngle: .radians(endAngle), endAngle: .radians(startAngle),
                 clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// One wedge with its content placed at the band's mid radius. All segments
/// share the parent ZStack's center, so frames just need to be square.
private struct WedgeSegment<Content: View>: View {
    let start: CGFloat
    let end: CGFloat
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let highlighted: Bool
    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        let mid = (start + end) / 2
        let midRadius = (innerRadius + outerRadius) / 2
        ZStack {
            WedgeShape(startAngle: start, endAngle: end,
                       innerRadius: innerRadius, outerRadius: outerRadius)
                .fill(highlighted ? Color.white.opacity(0.92) : .black.opacity(0.62))
            WedgeShape(startAngle: start, endAngle: end,
                       innerRadius: innerRadius, outerRadius: outerRadius)
                .stroke(highlighted ? accent : .white.opacity(0.14), lineWidth: 1)
            content()
                .offset(x: midRadius * cos(mid), y: midRadius * sin(mid))
        }
        .frame(width: outerRadius * 2, height: outerRadius * 2)
    }
}

struct WheelView: View {
    @ObservedObject var model: WheelViewModel
    var onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(model.appearance.dimOpacity)
            wheel.position(model.center)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var wheel: some View {
        let layout = model.layout
        let accent = Color(hex: model.appearance.accentHex)
        return ZStack {
            categoryWedges(layout: layout, accent: accent)
            childWedges(layout: layout, accent: accent)
            hub(layout: layout)
        }
        .frame(width: layout.outerOuterRadius * 2, height: layout.outerOuterRadius * 2)
    }

    private func categoryWedges(layout: WheelLayout, accent: Color) -> some View {
        let count = max(model.categories.count, 1)
        let halfStep = .pi / CGFloat(count)
        return ForEach(Array(model.categories.enumerated()), id: \.element.id) { i, category in
            let mid = WheelGeometry.categoryMidAngle(i, count: model.categories.count)
            let open = i == model.openCategoryIndex
            WedgeSegment(start: mid - halfStep, end: mid + halfStep,
                         innerRadius: layout.holeRadius,
                         outerRadius: layout.innerOuterRadius,
                         highlighted: open, accent: accent) {
                VStack(spacing: 3) {
                    Image(systemName: category.symbol)
                        .font(.system(size: 17, weight: .semibold))
                    Text(category.name)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(open ? Color.black : .white)
                .frame(maxWidth: max(layout.innerOuterRadius * 0.55, 60))
            }
        }
    }

    @ViewBuilder
    private func childWedges(layout: WheelLayout, accent: Color) -> some View {
        if let open = model.openCategory, let arc = model.childArc {
            ForEach(Array(open.items.enumerated()), id: \.element.id) { j, item in
                let hovered = j == model.hoveredChildIndex
                WedgeSegment(start: arc.start + arc.step * CGFloat(j),
                             end: arc.start + arc.step * CGFloat(j + 1),
                             innerRadius: layout.outerInnerRadius,
                             outerRadius: layout.outerOuterRadius,
                             highlighted: hovered, accent: accent) {
                    VStack(spacing: 2) {
                        childIcon(item, hovered: hovered)
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(hovered ? Color.black : .white)
                        if j < 9 {
                            Text("\(j + 1)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(hovered ? Color.black.opacity(0.55)
                                                         : .white.opacity(0.55))
                        }
                    }
                    .frame(maxWidth: 84)
                }
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            .animation(.spring(duration: 0.22), value: model.openCategoryIndex)
        }
    }

    @ViewBuilder
    private func childIcon(_ item: RingItem, hovered: Bool) -> some View {
        let side = model.appearance.iconSize * 0.62
        if let nsImage = IconProvider.nsImage(for: item) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
        } else {
            Image(systemName: IconProvider.fallbackSymbol(for: item))
                .font(.system(size: side * 0.62, weight: .medium))
                .foregroundStyle(hovered ? Color.black : .white)
        }
    }

    private func hub(layout: WheelLayout) -> some View {
        VStack(spacing: 2) {
            if let index = model.openCategoryIndex, let category = model.openCategory {
                Text(category.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(index + 1)/\(model.categories.count)")
                    .font(.system(size: 10, design: .rounded))
                    .opacity(0.6)
            } else {
                Text("MacRing")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: layout.holeRadius * 2 - 8, height: layout.holeRadius * 2 - 8)
        .background(Circle().fill(.black.opacity(0.7)))
        .overlay(Circle().strokeBorder(.white.opacity(0.15)))
    }
}
```

- [ ] **Step 3: Delete the v1 UI files and shim**

```bash
git rm Sources/MacRing/RingView.swift Sources/MacRing/RingViewModel.swift Sources/MacRingKit/RingGeometry.swift
```

In `Sources/MacRingKit/Model.swift`, delete the whole `legacyItems` computed property (and its comment). In `Sources/MacRingChecks/main.swift`, delete the `// MARK: Geometry` section (the seven `RingGeometry.*` checks and the `let c = CGPoint.zero` line — keep `// MARK: Wheel geometry`).

- [ ] **Step 4: Replace `Sources/MacRing/RingPanelController.swift` with:**

```swift
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
```

- [ ] **Step 5: Build and run checks**

Run: `swift build && swift run MacRingChecks`
Expected: `Build complete!`, all checks `ok`. If `SettingsWindow.swift` still references deleted types, fix per Task 1 Step 7 (the placeholder section must not reference `ItemsEditor`/`ItemRow`).

- [ ] **Step 6: Manual verification**

```bash
./scripts/bundle.sh && pkill -x MacRing || true; open dist/MacRing.app
```

Checklist (all must pass):
1. Hold ⌥⇧ → wheel appears: 4 category wedges, hub says "MacRing".
2. Move into a category wedge → it highlights white, hub shows its name + "k/4", children fan out on the outer arc with a spring.
3. Sweep across categories → outer arc re-fans per category.
4. Move out into a child wedge → highlights; release ⌥⇧ → the app/tool launches, wheel closes.
5. Hold ⌥⇧, hover a category, release → wheel stays (sticky); click a child → launches.
6. Flick far past the outer band → child still selected by angle; release launches it.
7. ⌃⌥Space → sticky wheel; digits: `2` opens category 2, then `1` launches its first item; Esc closes.
8. Near a screen corner → whole wheel stays on screen.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(ui): segmented two-band category wheel replaces v1 ring"
```

---

### Task 5: Settings v2 — category editor with app picker

**Files:**
- Modify: `Sources/MacRing/SettingsWindow.swift` (full replacement below)

**Interfaces:**
- Consumes: `RingCategory`, `RingItem`, `RingConfig.categories`, `AppScanner.scan()`, `InstalledApp`, `ConfigStore.shared` (`config`, `save`, `reload`, `configURL`, `lastError`, `changedNotification`), `ModifierHoldMonitor.isTrusted`, `promptForTrust()`, `Color(hex:)` (from WheelView.swift).
- Produces: `SettingsWindowController` with the same `convenience init()` (AppDelegate is untouched).

- [ ] **Step 1: Replace `Sources/MacRing/SettingsWindow.swift` with:**

```swift
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
```

- [ ] **Step 2: Build and run checks**

Run: `swift build && swift run MacRingChecks`
Expected: `Build complete!`, all checks pass.

- [ ] **Step 3: Manual verification**

```bash
./scripts/bundle.sh && pkill -x MacRing || true; open dist/MacRing.app
```

Checklist:
1. Menu bar → Settings… → Ring tab: four categories listed with badges; selecting shows its items.
2. Rename a category, wait ~1s, hold ⌥⇧ → wedge label updated.
3. Add App… → search "Notes" → click → appears in items and (after ~1s) on the wheel with the real icon.
4. Add Custom → Shell Command → set title/command; reorder with chevrons; delete with trash.
5. +/− add/remove categories; up/down reorder; wheel order matches (index 0 at top, clockwise).
6. Trigger and Appearance tabs still work (sliders live-update the wheel).
7. Open Config File → JSON has `"version": 2` and `categories`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(settings): category editor with installed-app picker"
```

---

### Task 6: Docs, bundle, final verification

**Files:**
- Modify: `README.md` (sections shown below)
- Modify: `docs/superpowers/specs/2026-07-18-macring-design.md` (one-line pointer)

- [ ] **Step 1: Update README**

In `README.md`: replace the intro paragraph and the **Features** first two bullets, and the **Config example**, with:

```markdown
# MacRing

A native macOS radial quick-launcher, inspired by [Orbs](https://orbs.studio).
Hold **⌥⇧** anywhere → a segmented wheel of your categories appears under the
cursor. Hover a category — its apps and tools fan out on an outer ring. Slide
to one, release → it runs.
```

Features bullets 1–2 become:

```markdown
- **Two-ring category wheel**: inner ring = categories (AI Tools,
  Photo & Video, Developer, System & Utilities by default); hovering fans the
  category's contents onto an outer arc. Esc or click-outside cancels. Works
  over full-screen apps.
- **Hotkey toggle**: ⌃⌥Space (default) opens a sticky wheel — digits pick a
  category then an item — so the app works even without Accessibility
  permission.
```

Config example becomes:

```markdown
​```json
{
  "categories": [
    { "name": "AI Tools", "symbol": "sparkles", "items": [
      { "title": "Claude", "type": "app", "value": "Claude" },
      { "title": "Perplexity", "type": "url", "value": "https://www.perplexity.ai" }
    ]}
  ]
}
​```

Item types: `app`, `url`, `file`, `shell`, `shortcut`. Optional `symbol` sets
an SF Symbol icon. v1 configs (flat `items` with submenus) migrate
automatically. Missing sections fall back to defaults; a broken file never
wipes your running config.
```

(Remove the zero-width characters around the code fence markers when writing the file.)

- [ ] **Step 2: Mark the v1 spec superseded**

Add under the title line of `docs/superpowers/specs/2026-07-18-macring-design.md`:

```markdown
> Ring-UI sections superseded by `2026-07-18-macring-v2-wheel-design.md` (v2 segmented wheel).
```

- [ ] **Step 3: Full verification pass**

```bash
swift run MacRingChecks && ./scripts/bundle.sh && pkill -x MacRing || true; open dist/MacRing.app
```

Re-run the Task 4 and Task 5 manual checklists end to end. All items must pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: v2 wheel README and spec pointers"
```

Leave the branch unmerged; the user reviews the wheel in person before merge.
