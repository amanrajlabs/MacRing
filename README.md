# MacRing

A native macOS radial quick-launcher, inspired by [Orbs](https://orbs.studio).
Hold **⌥⇧** anywhere → a segmented wheel of your categories appears under the
cursor. Hover a category — its apps and tools fan out on an outer ring. Slide
to one, release → it runs.

macOS 14+ · Apple Silicon & Intel · no account, no analytics, no network.

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
- **Launch at login**, opt-in from Settings.

## Install

Download the latest `MacRing-x.y.zip` from
[Releases](../../releases), unzip it, and drag **MacRing.app** to
`/Applications`.

### First launch: approving an unsigned app

MacRing is **ad-hoc signed but not notarized** — I'm not enrolled in the
$99/year Apple Developer Program. macOS therefore quarantines the download and
refuses the first launch with *"Apple could not verify MacRing is free of
malware."* This is Gatekeeper reporting the absence of a paid certificate, not
a detection of anything.

Approve it once, either way:

**System Settings** — try to open MacRing, then go to
Settings → Privacy & Security, scroll to *Security*, and click **Open Anyway**
next to the MacRing message. Confirm with Touch ID.

**Terminal** — strip the quarantine flag before the first launch:

```sh
xattr -dr com.apple.quarantine /Applications/MacRing.app
```

Prefer neither? [Build it from source](#build-from-source) — locally built
apps are never quarantined.

### Grant Accessibility

MacRing needs Accessibility to watch for the ⌥⇧ hold. On first launch it will
prompt; approve it in System Settings → Privacy & Security → Accessibility.

The ⌃⌥Space hotkey and the menu bar item work without this permission, so you
can skip it and still use the app.

> **Updating:** because the app is ad-hoc signed, its code signature changes
> with every build. macOS may stop trusting the old Accessibility grant after
> you replace the app. If the ⌥⇧ hold goes dead after an update, remove
> MacRing from the Accessibility list with **−**, then add it back with **+**.

## Usage

| Action | Result |
| --- | --- |
| Hold **⌥⇧** | Wheel opens under the cursor; release over an item to run it |
| **⌃⌥Space** | Sticky wheel — it stays open; pick with digits or the mouse |
| Click a category | Pins the wheel open on that category |
| **Esc** or click outside | Closes without running anything |

## Configuration

Settings live in the menu bar item, or edit the JSON directly at
`~/Library/Application Support/MacRing/config.json`:

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

> **A note on sharing configs:** `shell` items run arbitrary commands as you,
> with your permissions. Read any `config.json` you didn't write yourself
> before you use it.

## Build from source

Command Line Tools are enough — no Xcode required:

```sh
./scripts/bundle.sh              # debug build   → dist/MacRing.app
./scripts/bundle.sh universal    # arm64+x86_64  → dist/MacRing.app
./scripts/release.sh             # universal zip → dist/MacRing-x.y.zip
swift run MacRingChecks          # run the checks
```

## License

[MIT](LICENSE).
