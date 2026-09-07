# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

## About this project

- MonsterDeleter for macOS: a native macOS app where you summon a monster from Finder to eat a file, a folder or a whole selection (per-screen overlay, frame animation, trash only, never a permanent delete).
- The user-facing surface is a three-screen onboarding in the app window, a Settings window on Cmd-comma holding everything switchable, and an in-app guide (`docs/adr/0008-user-facing-surface.md`). Both icons are generated art composed by committed scripts (`docs/artwork.md`).
- The public architecture decisions live in `docs/adr/`. Read the relevant decisions before making product or architecture changes; do not depend on private development records.
- Upstream MonsterDeleter artwork is never committed here. Any personal copies belong in `assets/upstream/` (gitignored), outside the shipped packs.

## Build, test, run

- `swift build`, `swift test --no-parallel` (Swift Testing), `scripts/lint.sh`, `scripts/format.sh`.
- `scripts/build-app.sh` assembles `build/MonsterDeleter.app` from `Packaging/` (plist, icon from the committed 1024 px master, the menu bar template, built-in packs from `Packaging/packs/`) and then signs it with the Hardened Runtime, ad hoc unless `CODESIGN_IDENTITY` is set; `scripts/run.sh` also registers it with LaunchServices and launches it; `scripts/package.sh` wraps it as a zip (and a DMG). No Xcode project by design, for distribution too (`docs/adr/0001-swiftpm-app-bundle.md`, `docs/adr/0004-signing-and-packaging.md`).
- The version lives only in `Packaging/Info.plist`. `docs/releasing.md` owns the main-only candidate/publish workflow, exact artifact identity, credentials and retry rules. `scripts/notarize.sh` stays dormant without `NOTARY_PROFILE` unless `NOTARY_REQUIRED=1` makes missing setup an error.
- `scripts/self-test.sh` is the end-to-end check: build, a confirmed show and an Esc show on scratch files at (700, 400), phases, Trash and six checkpoint captures judged by the app (`AutoplaySelfTest`), exit 1 on any miss; `--update-references` rewrites `Tests/Fixtures/ShowReferences/`. CI runs it. `MONSTER_AUTOPLAY=<scratch path>[:<scratch path>...]` alone runs and judges one show; every variable is in the maintainer table in `docs/development.md`. It trashes the items.
- `MONSTER_EXPORT_PLACEHOLDER=<folder>` writes the placeholder pack as files and quits; edit its `pack.json`, zip the folder and drop it on the Settings window's Character section to test a user pack (`docs/development.md`).
- Packs: format, locations and the slicing cache are in `docs/adr/0003-character-packs.md`; the only decoding path is `PackManifest`, which never throws for a value. A pack that cannot be loaded is named in an alert and never replaced by the placeholder (`docs/adr/0007-no-placeholder-fallback.md`): `PackLibrary.current` is optional, the placeholder is not a listed pack, and a headless launch wears nothing at all.
- Where a show aims is three tiers in `Targeting/` (`docs/adr/0005-accessibility-target-tier.md`); the accessibility tier is off by default and needs the Accessibility permission.
- Pack art is generated against a flat magenta backdrop, a colour no character wears, and cut with `scripts/pack-sheet.sh` (window, crop, inset, grid, fade) over `scripts/lib/backdrop-matte.py`, which needs ffmpeg plus numpy and Pillow for `python3`. A sheet may also take an after-the-cut pass: `scripts/pack-strands.py` clears the alpha of the thin parts a render hangs under a prop, and the Cat pack's `rescuer.png` and `fly.png` depend on it, so re-cutting those two from their `pack-sheet.sh` arguments alone regrows the hairs under the vacuum's rim that the shipped sheets do not have. Why that shape and not a matting model is `docs/adr/0006-pack-art-on-a-magenta-backdrop.md`; `docs/artwork.md` preserves media provenance and the sheet preparation constraints. Do the generating in the gitignored `.pack-work/`: `kie-axi upload` refuses paths outside the worktree.
- Domain vocabulary is in `CONTEXT.md`; use its terms in code, tests and docs.
- File safety is native trash-only deletion with per-item results and cancellation before impact. Finder owns restoration; do not promise Put Back availability or exact restored names (`CONTEXT.md`, `Sources/MonsterDeleterKit/Bridges/TrashService.swift`).

## Sharp edges

- SwiftUI's `Image("name")` finds nothing in this bundle: there is no asset catalog by design, so a
  `MenuBarExtra(_:image:)` renders an empty 8 pt status item. `MenuBarIcon` loads the menu bar image
  through `NSImage(named:)`, which does search the bundle's resources, and a resource name ending in
  "Template" is what makes AppKit tint it.
- Both icons are composed from committed generated sources by `scripts/make-icon.sh --render`
  (`scripts/lib/compose-icon.py`, `scripts/lib/compose-menu-bar-icon.py`, Pillow needed). The app
  icon is artwork on the 824-in-1024 Apple grid; the menu bar one is an 18 pt template silhouette
  with holes in it. Do not make one from the other.
- The ask caption ("Goes to the Trash · Esc cancels") sits inside the `point` checkpoint's capture
  rect, so any change to `AskButtonsView` needs `scripts/self-test.sh --update-references`.
- Never read `NSEvent.mouseLocation` in the Services handler; it points at the menu item. The target point comes from `TargetPointMonitor`, and a missing or stale sample means the crosshair.
- `NSApp.servicesProvider` is set in `main.swift` before SwiftUI starts the run loop; the `NSServices` entry lives in `Packaging/Info.plist` and must keep `NSPortName` equal to the executable name.
- The overlay panel configuration is fixed (`docs/adr/0002-overlay-panel-configuration.md`); only `ignoresMouseEvents` and key status change per phase.
- `CAKeyframeAnimation` in `.discrete` mode needs one more key time than values; without it the last frame gets no time.
- Dictionaries keyed by an enum encode as flat arrays unless the enum adopts `CodingKeyRepresentable`; `pack.json` depends on the keyed form.
- A pack's `tint` replaces the ask bubble's *paper*, not its ink (`AskPalette.paper(_:)`), so it has to be a light colour; `ShippedPackTests` fails a built-in pack whose tint drops under 4.5:1 against the ink.
- Two more rules the art has to keep, both learned from the Cat pack's rescue (`docs/artwork.md`): no **broad near-black surface may face the backdrop**, because `backdrop-matte.py` measures magenta-ness over the pixel's own brightness, so such a surface picks up spill it has no brightness to divide by and lands mid-ramp at any `--lo` (the Cat vacuum's charcoal bumper, which came back at about half alpha across the front of the disc). This is not a ban on near-black pixels: of Kaiju's pixels at alpha >= 200, 5.76% of `rescuer.png`, 5.10% of `walk.png` and 10.0% of `explosion.png` are near-black (max(R,G,B) < 40), and UFO's explosion is 20.0%, and all of them matte cleanly and ship as the quality bar. And nothing thin may dangle off a character, because at `characterHeight` 250 pt a brush or a wire reads as a stray leg. Neither is recoverable in the cut.
- A crop narrower than the source scales a figure **up** (`288 / crop width`), which is the lever for a clip that framed the pair too small - but no crop undoes a figure the render itself cut off, and seedance re-frames its input still rather than opening on it, so margins have to be won in the clip's prompt. Measure clipping rather than asserting it: painted pixels at alpha >= 64 in a cell's own edge columns, summed over the sheet, against Kaiju's rescuer at 867 (worst frame 136), which ships as the quality bar.
- Making a pack, in the order that avoids rework: say in every seed prompt what fraction of the frame height the figure fills and that its feet are on the bottom edge, and settle the rescuer sheet's framing *first* - the rescuer shares one frame with the monster at a scale fixed across the sheet, so whatever it takes in height the monster cannot have, and every other sheet has to come down to what it can reach. Then, in `pack-sheet.sh`, the crop *width* sets the scale and the crop *height* only slides the frame down the cell (the fit binds on whichever axis is tighter, and the pad puts the frame's feet on the cell's bottom edge), so a crop height of `foot + 0.08` of the source lands any sheet's foot line on 0.920 of its cell and closes a size or foot-line mismatch for nothing. `ShippedPackTests.rescueHandover` is the guard.
- The slicing cache rescales a sheet as one image, so a frame whose paint reaches its cell's edge bleeds a little alpha into the neighbouring cell - which fails the explosion's must-be-empty last frame. Only the frames bordering that empty tail cell have to keep clear of the shared edge, not every frame: Kaiju's explosion touches its cell edges mid-bloom and ships with no inset, because by the tail the frames are faded. When a burst is still opaque there, `pack-sheet.sh --inset F` draws each frame at F of the cell, centred, and the pack's `explosionHeight` divided by F keeps the burst the same size on screen (`Packaging/packs/cat`).
- A pack's `kickImpactFrame` has a ceiling the manifest does not enforce: `exploding` lasts `sheetDuration - impactDelay`, and `ShowCheckpoint.explosion` samples 4.5 frame slots in, so from `kickImpactFrame` 11 on a 15-frame sheet that sample lands at or past `entered(rescuing)` and `ShowStage.snapshot` would draw the rescue instead, with no error and no reference to catch it in a `MONSTER_AUTOPLAY_PACK` evidence run. Cat's 10 is the highest that still works, with one frame slot to spare.
- `TrashFailureNotice` goes through `UNUserNotificationCenter`, which needs the app bundle: run the app through `scripts/run.sh`, never `swift run`. The first failure ever asks the user to allow notifications; a refusal falls back to an alert.
- A target the icon aiming resolved explodes on its icon rect's centre exactly: no rise, no sprite compensation (every built-in explosion sheet is painted centred in its cell, within 7 pt - `ShippedPackTests`), and no clamping. `explosionFanRise` is the original's 40 pt *pointer* offset and belongs to the fan of targets that did not resolve. Of the explosions, only that fan is clamped inside the screen, and only for two items or more (`Choreography.layout`): a fan at a corner piles up at the edge instead of moving off the file, while a burst on an icon, and a lone one, stay on their point and the panel clips them. The monster itself is always clamped, in both axes: icons spread wider than the screen leave no side it can stand clear of. The drawn hits stop at `ExplosionFan.maxHits` (19); every item is still trashed and the bubble still names the true count.
- Driving Finder in tests: System Events key codes for menus, `cliclick` clicks with a 120 ms hold; instant synthetic clicks through a click-through panel can wedge Finder in a drag. Drive a whole summon in one shell invocation: `TargetPointResolver.maxSampleAge` is 15 s, so an agent that stops to look at a screenshot between the right-click and the Services item loses the right-click and gets the crosshair. The ask's buttons take a synthetic click without acting on it; press one through the accessibility tree instead. A `cliclick` drag (`dd`, several `dm`, `du`) drops on whichever window is topmost at the drop point, so raise the window you are dropping on first - the zip drop zone is in the Settings window now.
- Bartender hides a fresh status item, which puts its menu off screen for System Events; `tell application "Bartender 6" to activate "io.github.kuan0808.MonsterDeleter-Item-0"` shows it, or quit Bartender for a screenshot and relaunch it after.
- An ad hoc build fails `spctl --assess` by design and still launches, since a local build has no quarantine flag. `codesign --timestamp` needs a Developer ID certificate and the network, so `scripts/lib/signing.sh` gives `--timestamp=none` to every other identity, ad hoc and personal team alike.
- `AppBundleTests` inspects `build/MonsterDeleter.app` only when it exists, so run `scripts/build-app.sh` before `swift test --no-parallel` (CI does). Universal artifact checks, prebuilt self-tests and recipient acceptance are documented in `docs/compatibility.md`. Package inspection inside a running Swift test needs its own SwiftPM scratch path to avoid waiting on the parent build lock.
- Screen captures need Screen Recording for the shell that runs `screencapture`; without it the PNG is black. `NSWorkspace.icon(forFile:)` is the way to capture the icon as shown.
- `URL.resourceValues` hands back a cached modification date within a run loop turn; the slicing cache reads it through `FileManager.attributesOfItem` for that reason.
- A checkpoint capture is the overlay panel's presentation layer tree rendered by the app (`ShowStage.snapshot`), which needs no Screen Recording and includes the hosted SwiftUI views; `CGWindowListCreateImage` and ScreenCaptureKit are not needed. Checkpoints sit mid frame slot and where the monster is slowest, and `ActorLayer` pins every animation's `beginTime` to the phase start (a late first commit used to shift a frame), so run-to-run drift is about zero against a 2 percent budget. A reference must not depend on the screen it was captured on: the flight ends past the screen's right edge, so the fly checkpoint is taken at the flight's first moment, where the monster is still on its spot (`ActorLayer` fills the frames `.both` and the move `.backwards` so that moment draws frame 0 there, not the model contents at the destination). The capture never draws "now": `CheckpointCapture` gives it the checkpoint's own moment on Core Animation's clock (the phase's `animationStart` plus the offset) and `ShowStage.snapshot(of:at:)` holds the layer tree there while it draws, so a capture task a loaded machine wakes a frame slot late still gets that frame and position. The committed references are 1x captures; a Retina target screen downsamples the hosted SwiftUI layers into the 1x capture and may drift the bubble and button glyph edges, which the self-test prints as a `skip:` note without failing on it.
- An app launched from a shell may never become active: macOS lets an app activate itself only when the user launched it, and never at the lock screen (`CGSessionCopyCurrentDictionary` shows `CGSSessionScreenIsLocked`). `NSApp.sendEvent` still delivers a key event to the overlay panel while inactive; a keyboard event posted through `CGEvent` would go to the frontmost app instead, so the self-test only posts one while the app is active. `AXIsProcessTrusted()` is inherited from the shell that launches the binary and is false under `open`. macOS 26 refused every self-activation of the accessory app at first launch; a Finder launch still orders the landing window in front.
- Every accessibility attribute is a synchronous message to Finder, so the count of messages is the whole cost: batch with `AXUIElementCopyMultipleAttributeValues`, ask containers for their selection instead of searching for names, and mind the traversal order (`docs/adr/0005-accessibility-target-tier.md`). The tree also has cycles; dedupe with `CFHash`.
- A tight `AXUIElementSetMessagingTimeout` is not protection: a timed-out call is indistinguishable from an absent attribute, so the reader silently prunes that branch and can resolve nothing. The budget in `TargetAimResolver` is what keeps the show waiting to a minimum; the messaging timeout only stops a wedged Finder from holding a thread for good.
- Accessibility positions are top-left of the menu bar screen with y down, AppKit's are bottom-left with y up; `AccessibilityGeometry` is the one conversion, and both are in points so a backing scale never enters it.
- `kAXTrustedCheckOptionPrompt` is imported as a mutable global that Swift 6 will not let a concurrent program read; its value is the string `"AXTrustedCheckOptionPrompt"`.
- TCC attributes an Accessibility grant to a process's *responsible* process, so the app inherits the terminal's grant when launched from a trusted shell and has none when launched with `responsibility_spawnattrs_setdisclaim`. This allows testing both responsibility cases without changing System Settings.
- Driving the Services item in tests: right-click, then Up (the last context-menu item is Services), Right, type-select, Return. Only one MonsterDeleter may run - a second instance, or another worktree's bundle with the same identifier, silently swallows the summon; `pkill -x MonsterDeleter` first, since `pgrep -f <abs path>` misses an instance started with a relative path.

## Engineering conventions

- Swift 6 language mode with strict concurrency (`-strict-concurrency=complete`). UI code is `@MainActor`.
- Value types by default; `@Observable` for state; no force unwraps outside tests; one type per file.
- Tests use Swift Testing (`import Testing`), never XCTest.
- SwiftUI for scenes and views. AppKit only where SwiftUI cannot do the job (the overlay panel, the Services provider, window levels), and every such bridge isolated in one type.
- Formatting: `.swift-format` at the repo root, applied by `scripts/format.sh`; `scripts/lint.sh` must pass before a commit. No SwiftLint, no third-party tooling.

## Skills and references

Vendored skills live in `.agents/skills/` (pins and licences in `.agents/skills/SKILLS-LOCK.md`) and are exposed as `.claude/skills/<name>`:

- `write-swift` - load whenever writing or reviewing any Swift: modeling, API design, Swift 6 idioms, Swift Testing.
- `swift-concurrency` - load when touching actors, `Sendable`, tasks, isolation, or a strict-concurrency compiler error.
- `swiftui-expert-skill` - load when building or debugging SwiftUI views, state flow, or view performance.
- `macos-design-guidelines` - load when designing any user-facing surface: windows, menus, toolbars, Services, keyboard behaviour, accessibility.

Reference sources:

- Apple documentation as agent-readable markdown: `https://sosumi.ai/documentation/<framework>/<symbol>` (same paths as developer.apple.com).
- Swift API Design Guidelines: https://www.swift.org/documentation/api-design-guidelines/
- Swift 6 migration guide: https://www.swift.org/migration/documentation/migrationguide/

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.

## Working method

## Implementation (test-first)
- Follow `docs/method/tdd.md` + `docs/method/tests.md` + `docs/method/mocking.md` strictly.
- Use the test seams agreed in the task brief or specification. If no seams were agreed,
  confirm them before writing new tests; do not guess or block silently.

## Using domain docs and the spec (consumer rules)
- Follow `docs/method/consumer-rules.md` strictly: name everything with CONTEXT.md's canonical terms,
  never drift to `_Avoid_` synonyms; read the docs/adr/ that touch the area you change, do not
  re-litigate recorded decisions; if you contradict an ADR, surface it explicitly, never silently override.
- Check against the brief/ticket acceptance criteria: missing, half-done, scope creep, or wrong.
- For bugs and merge conflicts, trace the original intent first (issue / ticket / commit / brief: why).

## Maintain the domain model as you go
- New term pinned down -> update CONTEXT.md (format: docs/method/CONTEXT-FORMAT.md).
- Hard-to-reverse + surprising + real-trade-off decision -> add an ADR (format: docs/method/ADR-FORMAT.md).

## Delivery

- After implementing and testing, commit to the task branch and follow the task's authorized
  review/delivery contract. A local-only preparation task does not authorize remote publication.

## Conventions
- No em dash. Use a plain dash "-" instead.
- Reproduce bugs E2E (as close to how an end user hits them as possible) before fixing.
- Not done until lint and tests are green. Fix lint, test failures, and test flakiness you encounter,
  even if not caused by your change.
- When end-to-end testing UI, be picky and obsessed with pixel perfection; fix clearly-off UI along the way.
- Prefer quality, simplicity, robustness, scalability, and long-term maintainability over development cost.
- Never auto-add your agent name as a commit co-author.
- Never hand-edit CHANGELOG.md or any file marked auto-generated.
