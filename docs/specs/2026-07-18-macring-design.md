# MacRing — Design

2026-07-18. Native macOS radial quick-launcher inspired by Orbs (orbs.studio).

## Goal

Hold a modifier combo (default ⌥⇧) anywhere in macOS → a ring of launcher
items appears under the cursor. Slide toward an item, release the modifiers →
it runs. Esc or click-outside cancels. Fully customizable: items, trigger,
and appearance live in a human-editable JSON config plus a Settings window.

## Non-goals (v1)

- Built-in mini-apps (timer, mirror, calculator…). Orbs ships 14; MacRing v1
  launches external things instead. The action model leaves room to add
  built-ins later.
- Pinned floating tools, drag-to-pin.
- Click-and-hold-anywhere trigger (needs an event tap swallowing clicks;
  deferred).

## Architecture

Swift Package (CLT-only machine — no Xcode, no XCTest), modeled on NotchDeck:

- `Sources/MacRingKit` — logic library, UI-free where possible:
  - `RingItem` / `RingAction`: Codable model. Action kinds: `app` (path or
    bundle id), `url`, `file`, `shell` (zsh -c), `shortcut` (macOS Shortcuts
    CLI), `submenu` (nested items).
  - `RingConfig`: items + `Appearance` (ring radius, icon size, accent hex,
    dim opacity) + `Trigger` (hold-modifier set, optional toggle hotkey
    keycode+mods). Codable, versioned.
  - `ConfigStore`: load/save JSON at
    `~/Library/Application Support/MacRing/config.json`; writes a default
    config on first run; posts a notification on save so UI reloads live.
  - `ActionRunner`: executes each action kind (NSWorkspace / Process).
  - `RingGeometry`: pure math — item positions on the circle, angle-based
    hit-testing with a center dead zone. Unit-checked.
- `Sources/MacRing` — the app:
  - `AppDelegate`: LSUIElement menu-bar app. Status item menu: Open Ring,
    Settings…, Open Config File, Reload Config, Quit.
  - `ModifierHoldMonitor`: global `flagsChanged` monitor (needs Accessibility
    trust; prompts once). Configured modifiers held → show ring at cursor;
    released → activate hovered item.
  - `HotkeyCenter`: Carbon `RegisterEventHotKey` toggle (default ⌃⌥Space) —
    works without Accessibility, so the app is usable even if AX is denied.
  - `RingPanelController`: borderless non-activating key `NSPanel`,
    `.screenSaver` level, transparent, sized to the cursor's screen. Hosts
    SwiftUI `RingView`. Polls `NSEvent.mouseLocation` on a 60 Hz timer for
    hover (no extra permissions). Esc closes; digits 1–9 quick-activate;
    click activates; click outside closes.
  - `RingView`: icons fanned on a circle, nearest-by-angle highlight beyond
    a dead zone, hovered title in the center. Submenu hover (300 ms dwell)
    or click drills in; back item in child rings. App icons via NSWorkspace,
    everything else SF Symbols.
  - `SettingsWindow`: SwiftUI editor — add/remove/reorder items, per-kind
    fields, appearance sliders, trigger picker. Saves through ConfigStore.
- `Sources/MacRingChecks` — plain executable (`swift run MacRingChecks`):
  config round-trip, geometry hit-tests, default config sanity.

## Build & distribution

`scripts/bundle.sh` → `swift build -c release`, assemble `dist/MacRing.app`
with `Resources/Info.plist`, generated `.icns` (`scripts/make-icon.swift`),
ad-hoc codesign. macOS 14+, Apple Silicon.

## Error handling

- Config parse failure → keep last good config, log, show alert from menu.
- AX permission missing → hold-trigger disabled, hotkey/menu still work;
  Settings shows a prompt button.
- Action failures (missing app, failing shell) → user notification via
  `NSUserNotification`-successor is overkill; log + NSSound beep.
