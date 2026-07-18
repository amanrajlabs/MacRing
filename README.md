# MacRing

A native macOS radial quick-launcher, inspired by [Orbs](https://orbs.studio).
Hold **⌥⇧** anywhere → a segmented wheel of your categories appears under the
cursor. Hover a category — its apps and tools fan out on an outer ring. Slide
to one, release → it runs.

## Features

- **Two-ring category wheel**: inner ring = categories (AI Tools,
  Photo & Video, Developer, System & Utilities by default); hovering fans the
  category's contents onto an outer arc. Esc or click-outside cancels. Works
  over full-screen apps.
- **Hotkey toggle**: ⌃⌥Space (default) opens a sticky wheel — digits pick a
  category then an item — so the app works even without Accessibility
  permission.
- **Menu bar item**: open the ring, settings, or the config file.
- **Any action type**: launch apps (path, bundle id, or bare name), open URLs,
  files/folders, run shell commands (`zsh`), and run macOS Shortcuts —
  organized into renameable categories.
- **Fully customizable**: Settings window (categories with an installed-app
  picker, trigger, wheel size, icon size, accent color, dim) plus a
  hand-editable JSON config at
  `~/Library/Application Support/MacRing/config.json`.
- Local-only. No account, no analytics, no network.

## Build

Command Line Tools only — no Xcode required:

```sh
./scripts/bundle.sh          # → dist/MacRing.app
swift run MacRingChecks      # run the checks
```

macOS 14+. First launch: grant Accessibility when prompted to enable the
hold-⌥⇧ trigger (the hotkey and menu bar work without it).

## Config example

```json
{
  "categories": [
    { "name": "AI Tools", "symbol": "sparkles", "items": [
      { "title": "Claude", "type": "app", "value": "Claude" },
      { "title": "Perplexity", "type": "url", "value": "https://www.perplexity.ai" }
    ]}
  ]
}
```

Item types: `app`, `url`, `file`, `shell`, `shortcut`. Optional `symbol` sets
an SF Symbol icon. v1 configs (flat `items` with submenus) migrate
automatically. Missing sections fall back to defaults; a broken file never
wipes your running config.
