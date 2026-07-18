# MacRing

A native macOS radial quick-launcher, inspired by [Orbs](https://orbs.studio).
Hold **⌥⇧** anywhere → a ring of your apps and tools appears under the cursor.
Slide toward an item, release → it runs.

## Features

- **Hold-to-open ring**: hold the configured modifiers (default ⌥⇧), flick,
  release. Esc or click-outside cancels. Works over full-screen apps.
- **Hotkey toggle**: ⌃⌥Space (default) opens a sticky ring — click or press
  1–9 to activate — so the app works even without Accessibility permission.
- **Menu bar item**: open the ring, settings, or the config file.
- **Any action type**: launch apps (path, bundle id, or bare name), open URLs,
  files/folders, run shell commands (`zsh`), run macOS Shortcuts, and nest
  submenus (dwell on one to fan it open).
- **Fully customizable**: Settings window (items, trigger, ring radius, icon
  size, accent color, dim) plus a hand-editable JSON config at
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
  "items": [
    { "title": "Safari", "type": "app", "value": "Safari" },
    { "title": "Deploy", "type": "shell", "value": "cd ~/proj && ./deploy.sh" },
    { "title": "Tools", "type": "submenu", "items": [
      { "title": "Screenshot", "type": "shell", "value": "screencapture -ic" }
    ]}
  ]
}
```

Item types: `app`, `url`, `file`, `shell`, `shortcut`, `submenu`. Optional
`symbol` sets an SF Symbol icon. Missing sections fall back to defaults; a
broken file never wipes your running config.
