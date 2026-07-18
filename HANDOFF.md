# Implementation Handoff — MacRing v2 Wheel

You are implementing a pre-approved feature in an existing macOS app. Do not
redesign anything — the design is decided and the plan is written. Your job is
faithful execution, task by task.

## Project

Repo root: the directory containing this file.
MacRing is a native macOS radial quick-launcher (menu bar app, SwiftPM,
macOS 14+). v1 works and is committed on the default branch. You are building
v2: an Orbs-style segmented two-ring category wheel.

## Read these two files FIRST, completely, before writing any code

1. `docs/superpowers/plans/2026-07-18-macring-v2-wheel.md` — the
   implementation plan. It contains COMPLETE code for every file, exact test
   assertions, commands with expected output, and a commit per task.
2. `docs/superpowers/specs/2026-07-18-macring-v2-wheel-design.md` — the spec
   (the "why" behind the plan; consult it whenever the plan seems ambiguous).

## Rules

- Work on branch `feature/v2-wheel` (Task 1 Step 1 creates it). Never commit
  to the default branch. Leave the branch unmerged when done.
- Execute tasks 1 through 6 strictly in order. Within a task, follow the
  steps and tick the `- [ ]` checkboxes in the plan file as you complete
  them. One commit per task, using the commit message given in the plan.
- This machine has Command Line Tools ONLY: no Xcode, no xcodebuild, no
  XCTest. Tests are plain assertions run via `swift run MacRingChecks`
  (exits 1 on failure). Build with `swift build`; bundle with
  `./scripts/bundle.sh` which produces `dist/MacRing.app`.
- `swift build` and `swift run MacRingChecks` must both pass at the END of
  every task before you commit.
- Use the code in the plan verbatim. If something in it fails to compile or
  a check fails, make the MINIMAL fix that preserves the specified interfaces
  and behavior, and record the deviation (file, what changed, why) in a
  running list for your final report. Do not restructure, rename, or
  "improve" beyond that.
- Do not touch: `Triggers.swift`, `ConfigStore.swift`, `AppDelegate.swift`,
  `scripts/`, `Resources/` — except where the plan explicitly instructs.
- Angle/coordinate convention (do not change): y-down view coordinates,
  angles in radians increasing clockwise, index 0 centered at the top
  (angle -pi/2).
- The user's live config at
  `~/Library/Application Support/MacRing/config.json` must keep working:
  v1 files migrate automatically (Task 1). Never delete or reset that file.

## Verification

- Automated: run the exact commands in each task's steps; outputs must match
  the "Expected:" lines.
- App relaunch for manual checks:
  `./scripts/bundle.sh && pkill -x MacRing || true; open dist/MacRing.app`
- The manual checklists in Tasks 4, 5, and 6 need a human at the keyboard
  (hold Option+Shift, hover, flick, press digit keys, press Esc). After
  finishing each of those tasks, relaunch the app as above, then STOP and ask
  the user to run that task's checklist before you proceed. Fix what they
  report, re-verify, then continue.

## Final report

When all 6 tasks are committed, report:

1. `git log --oneline` of the branch
2. Full `swift run MacRingChecks` output
3. The deviation list (or "none")
4. Anything from the manual checklists still unverified
