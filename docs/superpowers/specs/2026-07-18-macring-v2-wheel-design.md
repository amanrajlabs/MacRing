# MacRing v2 — Segmented Category Wheel (Spec)

2026-07-18. Supersedes the ring UI portions of `2026-07-18-macring-design.md`;
trigger system, panel infrastructure, config store, and build tooling carry
over unchanged.

## Goal

Replace the v1 floating-icon ring with an Orbs-style **segmented two-ring
wheel** (reference screenshot: dark translucent pie wedges, concentric bands):

- **Inner ring: categories only** (user decision). Wedge segments, each with an
  SF Symbol icon, name label, and number badge. Defaults: AI Tools,
  Photo & Video, Developer, System & Utilities.
- **Outer ring**: hovering a category immediately (no dwell) fans its
  apps/tools out as wedges on a second concentric band, arc-centered on the
  hovered category's angle. Hovering a different category re-fans the arc.
- **Center hub**: shows open category name and "k/N" position, "MacRing" when
  idle.
- **Settings**: manage categories (create, rename, delete, reorder, symbol)
  and their contents via a searchable installed-app picker plus manual entry
  for shell/URL/file/Shortcut actions.

## Decisions (user-confirmed)

1. Inner ring holds **categories only** — no direct app shortcuts on it.
2. **No built-in mini-tools** this iteration; add a `builtin` action kind +
   registry as the extension point, unimplemented behind it.
3. All four default categories ship pre-populated.
4. App linking = **installed-app picker + manual entry** for non-app actions.
5. Implementation will be done by a separate AI following the companion plan
   (`docs/superpowers/plans/2026-07-18-macring-v2-wheel.md`); iterate as needed.

## Interaction spec

Coordinates are y-down view coordinates; angles increase clockwise; index 0 /
first category is centered at the top (−π/2), matching v1 geometry.

Radial regions from the wheel center (`WheelLayout`, derived from
`appearance.ringRadius` R and `iconSize`):

| Region | Radius | Behavior on hover |
|---|---|---|
| hub | < 0.40·R | no child hovered; open category kept |
| inner band | 0.40·R … R | category by angle; changing it re-fans outer ring, clears child hover |
| gap | R … R+5 | child hover cleared; open category kept |
| outer band | R+5 … R+5+W | child by angle within the fanned arc |
| outside | > R+5+W | same as outer band (pure angular flick selection) |

W (outer band width) = max(iconSize + 34, 0.52·R).

- Category wedges: full circle divided equally; category i spans ±π/n around
  its mid angle.
- Child arc: each child wedge subtends ~78 pt of arc length at the outer
  band's mid radius, capped so the total never exceeds 2π; the arc is centered
  on the open category's mid angle. Cursor angles outside the arc hover
  nothing but keep the category open.
- **Activation**: modifier release runs the hovered child; with only a
  category open, the ring turns sticky (stays for click/digits). Click runs
  the hovered child or closes on empty space. Digits 1–9 pick a child of the
  open category, or open the k-th category when none is open. Esc closes the
  wheel. Hotkey/menu-opened wheels are sticky as in v1.
- Visuals: dark translucent wedges (~0.6 black, 0.85 hovered) with 1 pt
  separators, hovered wedge fills white with dark icon/label (per reference
  screenshot), accent color for glow/borders, springy fan-out animation for
  the outer ring, dimmed backdrop (existing `dimOpacity`).

## Data model (v2)

```
RingConfig  { version: 2, trigger, appearance, categories: [RingCategory] }
RingCategory { id, name, symbol, items: [RingItem] }
RingItem     { id, title, symbol?, action }   // unchanged
RingAction   { app | url | file | shell | shortcut | submenu | builtin }
```

- `submenu` survives only for decoding v1 files; v2 UI neither renders nor
  offers it inside categories.
- `builtin(id)` routes to `BuiltinRegistry` (id → closure map, empty in v2;
  unknown ids log + beep). This is the future mini-tools extension point.
- **Migration** (automatic, in `RingConfig.init(from:)`): a file with
  `categories` decodes as v2. A file with legacy root `items` maps: root
  submenu → category (name/symbol/children, nested submenus flattened out);
  root leaves → one "General" category (symbol `star`), placed first. Config
  is re-saved as v2 on next save.

## Settings (v2)

Three tabs: **Ring** (category editor), **Trigger** (unchanged v1 section),
**Appearance** (v1 sliders; radius label becomes "Wheel size").

Ring tab: category list (left) with add/delete/reorder/rename and symbol
field; selected category's items (right) with reorder/edit/delete;
**Add App…** opens a searchable sheet of installed apps (AppScanner:
/Applications one level deep, /System/Applications, …/Utilities,
~/Applications); **Add Custom** inserts an editable url/file/shell/shortcut
row. Existing auto-save/reload/config-file plumbing is reused.

## Non-goals

Built-in tool implementations, pagination ("8/9" style pages), per-category
colors, click-and-hold trigger, pinned floating tools, hotkey recorder.

## Error handling

Unchanged from v1 (config-keeps-last-good, beep+log on action failure).
Empty categories render an empty outer arc; an empty config renders hub only.
Categories beyond 10 get a Settings caption warning that wedges get cramped.

## Verification

Model/geometry/scanner via `swift run MacRingChecks` (added cases in the
plan). UI via build + scripted relaunch + a manual checklist (hold ⌥⇧, hover
category, fan, flick, release; digits; Esc; settings round-trip).
