// Plain-executable checks (CLT-only machine, no XCTest): `swift run MacRingChecks`.
import AppKit
import CoreGraphics
import Foundation
import MacRingKit

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("ok   \(name)")
    } else {
        failures += 1
        print("FAIL \(name)")
    }
}

func approx(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
    abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
}

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

// MARK: Geometry

let c = CGPoint.zero
check(approx(RingGeometry.position(index: 0, count: 4, radius: 100, center: c),
             CGPoint(x: 0, y: -100)), "index 0 sits at the top")
check(approx(RingGeometry.position(index: 1, count: 4, radius: 100, center: c),
             CGPoint(x: 100, y: 0)), "index 1 is clockwise-right")
check(RingGeometry.hitIndex(center: c, point: CGPoint(x: 70, y: 0), count: 4, deadZone: 30) == 1,
      "hit right selects index 1")
check(RingGeometry.hitIndex(center: c, point: CGPoint(x: 0, y: -70), count: 4, deadZone: 30) == 0,
      "hit top selects index 0")
check(RingGeometry.hitIndex(center: c, point: CGPoint(x: -70, y: 0), count: 4, deadZone: 30) == 3,
      "hit left selects index 3")
check(RingGeometry.hitIndex(center: c, point: CGPoint(x: 10, y: 0), count: 4, deadZone: 30) == nil,
      "dead zone selects nothing")
check(RingGeometry.hitIndex(center: c, point: CGPoint(x: 70, y: 0), count: 0, deadZone: 30) == nil,
      "empty ring selects nothing")
// Slightly counterclockwise of top must still snap to index 0, not wrap.
check(RingGeometry.hitIndex(center: c, point: CGPoint(x: -10, y: -70), count: 8, deadZone: 30) == 0,
      "just left of top snaps to index 0")

// MARK: Modifiers

check(Modifiers.nsFlags(["option", "shift"]) == [.option, .shift], "ns flag mapping")
check(Modifiers.symbolString(["control", "option", "shift", "command"]) == "⌃⌥⇧⌘",
      "symbol string ordering")
check(Modifiers.carbonFlags(["control"]) != 0 && Modifiers.carbonFlags(["bogus"]) == 0,
      "carbon flag mapping")

// MARK: App resolution (system apps that exist on every macOS install)

check(ActionRunner.resolveAppURL("/System/Applications/Notes.app") != nil,
      "resolve by absolute path")
check(ActionRunner.resolveAppURL("Notes") != nil, "resolve by bare name")
check(ActionRunner.resolveAppURL("com.apple.finder") != nil, "resolve by bundle id")
check(ActionRunner.resolveAppURL("/nope/missing.app") == nil, "missing path resolves nil")

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
