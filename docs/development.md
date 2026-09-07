# Developing MonsterDeleter

Build and test commands run from the repository root. For app usage, see the [README](../README.md); for public distribution, see [releasing](releasing.md).

## Requirements

To run: macOS 15 or later, on Apple silicon or Intel. The packaged app is universal.
See [compatibility checks and recipient acceptance](compatibility.md) for what the automated
gates cover and what still needs a hands-on check.

To build: Xcode 26.5 (Swift 6.3) on a compatible build host (macOS 26.2 or later).
The recipient does not need Xcode. No package dependencies or additional build framework.

## Build and install

```sh
swift build                 # library, app executable
swift test --no-parallel    # Swift Testing suite (the bundle tests skip until build-app.sh has run)
scripts/lint.sh             # swift-format lint, must pass before a commit
scripts/format.sh           # swift-format in place
scripts/build-app.sh        # builds arm64 + x86_64, assembles and signs build/MonsterDeleter.app (release)
scripts/run.sh              # build-app.sh, registers the bundle with LaunchServices, launches it
scripts/package.sh          # build-app.sh, then build/MonsterDeleter-<version>.zip (PACKAGE_DMG=1 adds a DMG)
```

CI pins macOS 26 and Xcode 26.5 for the build, bundle, test, lint, self-test and packaging steps on every pull request and push to `main` and uploads the ad hoc zip and DMG, and the self-test's logs and captures, as workflow artifacts: `.github/workflows/ci.yml`. Separate macOS 15 arm64 and Intel jobs
verify checksums and run the identical archived app without rebuilding it.

To install the personal build, run `scripts/package.sh` and copy `build/MonsterDeleter.app` to `/Applications` (or run `PACKAGE_DMG=1 scripts/package.sh`, open the DMG and drag it there), then launch it once; the Finder Services item appears as soon as the app is running, no login item or Finder restart needed. The first launch opens the app window on its introduction - what the app does, where the Finder Services item is, and the offer of icon aiming - and keeps doing so until that has been finished or skipped; it is ordered in front and becomes key on the first click. A locally built app carries no quarantine flag, so Gatekeeper never prompts even though the ad hoc signature would fail `spctl --assess`. The app lives in the menu bar (no Dock icon). Its menu has **Open MonsterDeleter**, **Play Demo**, which creates a scratch file and runs the show with the crosshair, **Settings…** (⌘,) and **Quit**. Nothing switchable is in the menu: the character, the zip install, icon aiming and the sound are all in the settings window, which is where macOS keeps preferences.

To test an existing bundle without rebuilding it:

```sh
scripts/check-app.sh /path/to/MonsterDeleter.app
scripts/self-test.sh --prebuilt-app /path/to/MonsterDeleter.app
scripts/test-packaging.sh   # also rejects missing and thin disposable artifacts
```

The self-test logs the executable hash and active slice. Its normal invocation still builds
and runs the confirmed and Esc shows. Keep only one MonsterDeleter running during these checks.

### Signing

`scripts/build-app.sh` assembles the bundle (executable, `Packaging/Info.plist`, the icon, every built-in pack folder under `Packaging/packs/`) and then signs it in one `codesign` call with the Hardened Runtime and `Packaging/MonsterDeleter.entitlements`. The identity comes from `CODESIGN_IDENTITY` and defaults to ad hoc (`-`):

```sh
scripts/build-app.sh                                              # ad hoc, this Mac only
CODESIGN_IDENTITY="Apple Development: ..." scripts/build-app.sh   # personal team, keeps TCC grants across rebuilds
CODESIGN_IDENTITY="Developer ID Application: ..." scripts/package.sh   # a build meant for another Mac
```

The bundle identifier and entitlements are the same on every build, so LaunchServices and TCC keep one record for the app. A secure timestamp is added only for a `Developer ID Application: ...` identity (`scripts/lib/signing.sh`), because that is the one Apple's notary service requires; an ad hoc or personal-team build passes `--timestamp=none` and signs without a network. A Developer ID build is notarizable as is: `scripts/notarize.sh` submits the zip with `notarytool`, staples the ticket and zips the app again. It does nothing unless `NOTARY_PROFILE` names a `notarytool` keychain profile, which needs the paid Apple Developer Program, so it stays dormant until public distribution (`docs/adr/0004-signing-and-packaging.md`).

### Version and icon

The version is `CFBundleShortVersionString` in `Packaging/Info.plist` (with `CFBundleVersion` as the build number); the packaging script reads it from there, and nothing else carries it. The two icons are generated art composed by committed scripts: the app icon is the Kaiju character on Apple's icon grid, and the menu bar icon is an 18 pt template silhouette macOS tints itself. `scripts/make-icon.sh --render` recomposes both from the sources in `Packaging/Icon/`, and `scripts/build-app.sh` turns the master into `AppIcon.icns` with `sips` and `iconutil` and copies the template into the bundle on every build. See [media provenance and icon composition](artwork.md).

### Self-test

```sh
scripts/self-test.sh                       # build, then two shows on scratch files, judged; exit 1 on any miss
scripts/self-test.sh --update-references   # the same, writing the six checkpoint PNGs over Tests/Fixtures/ShowReferences/
```

The first show confirms on a file and a folder: every phase must fire in order within 150 ms of the choreography's table (the button press gets 500 ms more, for `Task.sleep`), both items must be in the Trash afterwards, and six checkpoint captures of the overlay (walk, point, kick, explosion, rescuer, fly, one per sheet) must each match the committed reference within 2 percent of their pixels. The second show presses Esc during the ask and must end cancelled with both items still there. Both shows always play the placeholder pack with no swap button, so the captures are the same on every Mac; the target point is fixed at (700, 400) so they fit any screen, and the fly is captured at the flight's first moment, since the flight ends past the screen's right edge and so crosses a screen's width of its own in the same two seconds. A capture is the overlay panel's layer tree rendered by the app itself, one pixel per point, so no Screen Recording grant is needed; it is drawn at the checkpoint's own moment on the show's clock, with the layer tree held there, so a busy machine that wakes the capture a frame slot late still gets that frame rather than the next one. The app judges its own show (`AutoplaySelfTest`) and prints one `FAIL:` line per problem; the script adds the exit status and an outside check that the scratch items are gone or still there. Logs and captures land under `build/self-test/`. CI runs it on every push and uploads that folder.

`MONSTER_AUTOPLAY_SHOWS=<n>` repeats the show in one process to measure memory, and judges every one of those shows against the same 150 ms window. That window is the show's own timing plus however late the host wakes a sleeping task: on a Mac with tens of milliseconds of wake latency the later shows of a repeat run sit at the edge of it and one can exit 1 without anything being wrong with the show. The self-test plays one show per process and is the gate; a repeat run is for the memory column.

Two checks depend on the session: the overlay panel can only be checked for keyboard focus, and a real keyboard Esc only posted, while the app is active, and macOS lets an app activate itself only when the user launched it (never at the lock screen, and not on a CI runner without an Accessibility grant). The self-test says which of these it skipped, with a `skip:` line, and sends Esc straight to the app instead. The committed references are 1x captures: a Retina target screen caches the hosted SwiftUI layers at its own scale and downsamples them into the 1x capture, which can move the glyph edges of the bubble and the buttons, so the self-test prints the target screen's scale at summon and adds a `skip:` line saying the comparison is only reliable at 1x (it still compares, and the sprites are unaffected). When a checkpoint moves on purpose (a layout change, a new placeholder frame), run `scripts/self-test.sh --update-references`, look at the six PNGs, and commit them with the change.

The app under the self-test is `MONSTER_AUTOPLAY`, which any evidence capture can drive by hand:

```sh
MONSTER_AUTOPLAY=/path/to/scratch.txt:/path/to/scratch-folder MONSTER_AUTOPLAY_POINT=1720,720 \
  build/MonsterDeleter.app/Contents/MacOS/MonsterDeleter
```

runs one show on those colon-separated paths (one or more) at that AppKit global point (default: the main screen's centre), presses the button two seconds after the bubble appears (`MONSTER_AUTOPLAY_CONFIRM_DELAY`), prints every event with its time and every problem it found, and exits with 0 only when the show ran to the table and the items are in the Trash. It trashes the items, so point it at scratch files. The variables in the maintainer table below choose Esc over the button, write or compare checkpoints, and repeat the show.

## Aiming

The show aims at the target in three tiers, best first, each falling silently to the one below it:

1. **The Finder icon.** With **Aim at each file's icon** turned on in Settings and the Accessibility permission granted, the app reads where Finder draws each selected item and the monster walks to the icon itself rather than to wherever on the row or label you happened to click. Each item of a selection explodes on its own icon; anything that cannot be resolved is fanned around the right-click as before. A show runs on one screen, so a selection spread over two displays keeps the icons on the screen you right-clicked and fans the rest, and an item Finder names ambiguously and gives no path for - a folder `Report` beside a `Report.pdf` with its extension hidden - is fanned rather than aimed at the wrong icon.
2. **The right-click.** The default, and what every install does until the preference is turned on: the last right-click, which lands on the item in every Finder view. No permission needed.
3. **The crosshair.** Every screen dims and you click the target yourself, when neither of the two above has anything to offer (the demo, or a right-click older than 15 seconds).

**What the permission gives the app.** The Accessibility permission lets an app read other apps' windows. MonsterDeleter reads **the contents of Finder's windows, nothing else, and only while a show is being summoned**: one bounded read of the selected items' positions, at most 150 ms, then it stops. Nothing is stored and nothing leaves your Mac.

The switch is the whole request: turning **Aim at each file's icon** on in Settings lets macOS raise its own prompt, and the app never asks at launch or during a show and never opens System Settings by itself. The switch shows the **effective** state - the wish and the grant together - so with the permission missing it reads off, because that is the truth: the monster is still aiming at your right-click. What you asked for is remembered even so, and the row under the switch says what is missing, offers the exact Accessibility pane (macOS shows its own prompt at most once per app, so a user who dismissed it needs that pane) and offers **Stop Asking** to withdraw the request, which is the way out of that row now that the switch cannot be flipped back. Both Settings and the introduction briefly show **Waiting for macOS…** when you request permission. If the app observes the system prompt take focus, both show **Waiting for your answer in macOS…** until a grant, your return to the app or an action on the row settles it. If no prompt can be identified, the row offers the pane instead. The app bringing itself forward for a show or alert never counts as your answer; an abandoned wait eventually returns to the ordinary permission warning. The row, and the introduction's third step, re-read the grant while they are on screen, so the switch turns itself on the moment the permission is granted in System Settings and back off if it is revoked, with no relaunch; declining costs only the precision: the monster aims at your right-click and the explosions gather there.



## Character packs

A pack is a folder: `pack.json` plus six sprite sheets (walk, point, kick, explosion, rescuer, fly; 5 x 3 grids by default) and three sounds (bgm, voice, explosion). Every field of `pack.json` is optional and falls back to the placeholder's value: `name`, `description`, `framesPerSecond` (8), `characterHeight` (250), `explosionHeight` (150), `explosionFanRadius` (75, the spacing of a selection's explosion fan), `walkSeconds` (4.5), `flySeconds` (2), `pointFrames` (`[11, 14]`), `kickImpactFrame` (5), `sheets` (`{"walk": {"file": "walk.png", "columns": 5, "rows": 3}, ...}`), `audio` (`{"bgm": {"file": "bgm.wav", "volume": 0.5, "loops": true}, ...}`), `texts` (`bubble`, `bubbleMany` with a `{count}` token for a selection, `confirm`, `alternate`) and `tint` (`#RRGGBB`, paints the bubble and buttons). Unknown fields are ignored; a malformed value is logged and replaced by its default. A file the manifest names must exist; a role it leaves out, or gives no `file` for, uses `<role>.png` or `<role>.wav` from the folder when present and the placeholder otherwise, so a `pack.json` alone is a re-skin and an entry may carry only a grid or a volume.

- Built-in packs ship in the app bundle; user packs live in `~/Library/Application Support/MonsterDeleter/packs/<name>/`. A pack that cannot be loaded is reported by name with its reason, and the app keeps or moves to a character that works - never to stand-in art (`docs/adr/0007-no-placeholder-fallback.md`).
- Built-in packs: three folder packs made with `scripts/pack-sheet.sh` under `Packaging/packs/`, of which **Kaiju** is the one a fresh install wears - **Kaiju**, a spiked vinyl toy monster and the helmeted rescuer who hauls it away; **Cat**, an upright ginger toy cat who swats files off the desk and the robot vacuum that carries it away; and **UFO**, a toy astronaut who boots files into a black hole and the flying saucer that beams the astronaut up. See [media provenance and sheet preparation](artwork.md).
- Drop one or more zips on the Character section of the settings window (or use **Choose Zip…**) to install them. A zip must contain `pack.json`, at its root or inside one folder as Finder's Compress makes it, and every file the manifest names, and it must stay under 1000 files and 512 MB unpacked, measured both from the listing and from what it really unpacks to in the scratch folder; anything else is rejected with the reason. The window shows one line per dropped file, in drop order. Installing a zip with the same name replaces the pack. An installed pack becomes the current one once it has loaded, unless another pack was chosen in the meantime.
- On first use each sheet is scaled so every frame is twice its displayed height and cached under `~/Library/Application Support/MonsterDeleter/cache/`; editing a sheet replaces its cache entry.
- The swap button beside the ask bubble, shown whenever the list holds a second pack, which a fresh install already does, dresses the running show in the next pack without touching its timing. A chosen pack is remembered once it has loaded; the first-run pack is not written down, so a later release's first-run pack still reaches anyone who never picked one.

The generated placeholder pack is not in the list and cannot be chosen. It has two jobs left: the self-test judges its checkpoints against it, and `MONSTER_EXPORT_PLACEHOLDER=/path/to/folder build/MonsterDeleter.app/Contents/MacOS/MonsterDeleter` writes it out as files and quits, which is the template for authoring a pack.

## Why a SwiftPM package and no Xcode project

`swift build` and `swift test` stay first-class, the whole build is reviewable in `Package.swift` plus a handful of small shell scripts, and there is no generated project to keep in sync. `scripts/build-app.sh` assembles the bundle from `Packaging/Info.plist` and `Packaging/MonsterDeleter.entitlements`, draws the icon through `scripts/make-icon.sh`, copies the built-in packs and signs; `scripts/package.sh` writes the release zip and DMG and `scripts/notarize.sh` is the one step public distribution adds, so no Xcode project is needed for distribution either. See `docs/adr/0001-swiftpm-app-bundle.md` and `docs/adr/0004-signing-and-packaging.md`.

## How a show works

One show is one run of the phase machine, `Sources/MonsterDeleterKit/Show/ShowMachine.swift`, a pure value that reads a clock and returns events; everything visible or audible hangs off those events in `ShowDirector`.

1. **Summon.** The Finder Services item hands the selection to `ServicesProvider`; `AppDelegate` sorts it, resolves where the show aims with `TargetAimResolver` - the Finder icons when the preference and the permission allow (`FinderIconReader`), the last right-click otherwise (`TargetPointMonitor`, `TargetPointResolver`) - and calls `ShowDirector.summon`. The director builds a `ShowStage` (one `OverlayPanel` per screen, `ActorLayer`s for the sprites) and an `AudioPlayer` for the chosen pack, and starts a `ShowMachine` with the aim's target point and the item count.
2. **Aiming, only without a point.** The machine starts in `aiming`: every screen dims behind a crosshair and the panel takes clicks and Esc. A click calls `aim(at:)`, which enters `entering`, 500 ms of backdrop fade, then `walking`.
3. **Walking.** `Choreography.layout` picks the side the monster fits on, where it stands (30 pt beside the target, from the resolved icons' outer edge where there are any, and 50 pt lower) and where every explosion goes (`ExplosionFan`). The stage plays the walk sheet in a loop and slides the layer in over 4.5 s with the OutQuad curve, click-through.
4. **Asking.** After the walk the machine enters `asking`, the one interactive phase besides aiming: the panel becomes key, the point frames play once (500 ms) and `askBubbleDue` puts up the bubble, the two buttons, a fixed caption under them in the app's own words ("Goes to the Trash · Esc cancels", which no pack can overwrite) and, with a second pack in the list, the swap button. Nothing is timed from here: the machine's `nextDeadline` is `nil` until the user acts. Either button calls `confirm()`; Esc or a click outside calls `cancel()`, which ends the show with the selection untouched. A swap dresses the stage in the next pack and leaves the machine alone.
5. **Kicking, exploding.** `confirm()` enters `kicking`; at the pack's impact frame (625 ms for the placeholder, whose `kickImpactFrame` is 5) `exploding` starts one explosion per item - a resolved target on its own icon, the rest fanned around the aim's fan centre - plays the sound and moves the whole selection to the Trash in one `NSWorkspace.recycle` call.
6. **Rescuing, flying, done.** The rescuer sheet plays for 1.875 s; then the pair flies out past the screen edge over 2 s with the InQuad curve, and `done` tears the stage down, stops the audio, hands keyboard focus back and reports the trash outcome, which becomes the trash failure notice when something stayed put.

Every timed phase advances from its scheduled start, not from the tick that noticed it, so a late tick never accumulates drift; `ShowMachineTests` drives the machine with a hand-advanced clock through every transition, cancel path and selection size, and `ChoreographyTests` pins every constant and checks the layout for every count from one to two thousand. The timetable the self-test judges a real run against is `ShowTimetable`, built from the same `Choreography`.

## Maintainer reference

| Kind | Name | What it does |
|---|---|---|
| Script | `scripts/build-app.sh [debug\|release]` | Builds the executable, assembles `build/MonsterDeleter.app` (plist, both icons, built-in packs) and signs it with the Hardened Runtime. |
| Script | `scripts/run.sh [debug\|release]` | `build-app.sh`, then registers the bundle with LaunchServices and launches it; extra environment passes through. |
| Script | `scripts/package.sh [debug\|release]` | `build-app.sh`, then `build/MonsterDeleter-<version>.zip`, and a DMG with `PACKAGE_DMG=1`. |
| Script | `scripts/notarize.sh` | Submits the zip with `notarytool`, staples and re-zips; `PACKAGE_DMG=1` also wraps and notarizes the stapled app as a DMG. Missing `NOTARY_PROFILE` fails with `NOTARY_REQUIRED=1`, otherwise does nothing. |
| Script | `scripts/self-test.sh [options]` | See [Self-test](#self-test) for confirmation, cancellation and reference updates, and [prebuilt artifact checks](compatibility.md#reproduce-the-gates) to run an existing bundle without rebuilding. |
| Script | `scripts/pack-sheet.sh <clip> <sheet.png> [options]` | Cuts a motion clip into one pack sprite sheet: window, crop, grid, backdrop matte (`scripts/lib/backdrop-matte.py`), fade. Its own header lists the options and the tools it needs; `docs/adr/0006-pack-art-on-a-magenta-backdrop.md` is why it mattes rather than keys, and [sheet preparation](artwork.md#sheet-preparation) documents the art constraints. |
| Script | `scripts/pack-strands.py <sheet.png> ... [--columns C] [--rows R] [--wide W]` | An after-the-cut, alpha-only pass that clears the thin parts a render hangs under the Cat pack's robot vacuum, applied to `Packaging/packs/cat/rescuer.png` and `fly.png`: re-cutting those two from their `pack-sheet.sh` arguments alone regrows the hairs. Idempotent, and the rule is that prop's, so it erases legitimate paint on art it was not written for. |
| Script | `scripts/make-icon.sh [--render]` | Turns the committed 1024 px master into `build/AppIcon.icns`; `--render` recomposes the master and the menu bar template from the generated sources in `Packaging/Icon/` (`scripts/lib/compose-icon.py`, `scripts/lib/compose-menu-bar-icon.py`, both need Pillow). |
| Script | `scripts/lint.sh`, `scripts/format.sh` | `swift-format` lint (must pass before a commit) and in-place formatting, config in `.swift-format`. |
| Script | `scripts/lib/signing.sh <identity>` | Prints the `--timestamp` flag for an identity: a secure timestamp for Developer ID only. |
| Command | `swift build`, `swift test` | The library, the executable and the Swift Testing suite; run `scripts/build-app.sh` first so the bundle tests run rather than skip. |
| Variable | `CODESIGN_IDENTITY` | The signing identity for `build-app.sh` (default `-`, ad hoc). |
| Variable | `PACKAGE_DMG=1` | Makes `package.sh` write a DMG beside the zip. |
| Variable | `NOTARY_PROFILE` | The `notarytool` keychain profile that wakes `notarize.sh`. |
| Variable | `MONSTER_AUTOPLAY=<path>[:<path>...]` | Plays one show on that selection at launch, judges it and exits with its status. Trashes the items. |
| Variable | `MONSTER_AUTOPLAY_POINT=x,y` | The target point in AppKit global coordinates (default: main screen centre; without any screen the show aims with the crosshair). |
| Variable | `MONSTER_AUTOPLAY_CONFIRM_DELAY=<seconds>` | How long after the bubble the answer comes (default 2). |
| Variable | `MONSTER_AUTOPLAY_ANSWER=esc` | Press Esc instead of the button; the show must end cancelled with the items untouched. |
| Variable | `MONSTER_AUTOPLAY_PACK=<pack id>` | Play the show in that pack (`builtIn/kaiju`) instead of the placeholder an autoplay run otherwise forces, for capturing a pack's own evidence. An id no pack answers to ends the run. |
| Variable | `MONSTER_AUTOPLAY_SNAPSHOTS=<folder>` | Write the six checkpoint captures there as PNGs. |
| Variable | `MONSTER_AUTOPLAY_REFERENCE=<folder>` | Compare each checkpoint with the PNG of the same name there; more than 2 percent of pixels different is a failure. |
| Variable | `MONSTER_AUTOPLAY_SHOWS=<n>` | Play the show n times in one process, recreating the scratch items between shows, and print the memory footprint after each. Timing-sensitive: it judges every show against the same 150 ms window, so a host whose timers wake tens of milliseconds late fails a transition. Read it for the memory column; the gate is `scripts/self-test.sh`. |
| Variable | `MONSTER_EXPORT_PLACEHOLDER=<folder>` | Write the placeholder pack as files there and quit: the template for a pack. |

## Layout

- `Sources/MonsterDeleterKit/` is the library: the choreography constants, layout and explosion fan, the three aiming tiers under `Targeting/`, the pack format (`Pack/`: descriptor, manifest decoding, placeholder pack, folder packs, the slicing cache, the pack library, zip install), the pure `ShowMachine`, target point resolution, selection ordering, the SwiftUI ask, introduction, home, settings and guide views with the two drawn illustrations (`ServicesMenuArt`, `AimingArt`), the self-test (`Autoplay/`: options, timetable, trace, checkpoints, capture comparison, the driver), and every AppKit, Core Animation, AVFoundation and UserNotifications bridge under `Bridges/` (each documented with why SwiftUI could not do the job).
- `Sources/MonsterDeleter/` is the executable: `main.swift` installs the Services provider before the run loop, `MenuBarApp` is the `MenuBarExtra`, `AppDelegate` wires the pieces.
- `Packaging/` holds `Info.plist`, the entitlements, the icon sources with the app icon master and the menu bar template (`Icon/`) and the built-in pack folders (`packs/`); `scripts/` assembles, signs, packages, self-tests and, later, notarizes the bundle, and cuts pack sheets (`pack-sheet.sh`).
- `Tests/MonsterDeleterKitTests/` covers the timing table, layout and the explosion fan for every selection size, machine transitions, cancellation and swap-shaped pauses, the Esc key path, selection ordering, trash failure aggregation and the notice copy, the three aiming tiers and their budget, the accessibility coordinate conversion across a multi-screen arrangement, the icon matching rule, the pack format and its defaults, folder packs, the slicing cache, the pack library, zip validation, the placeholder pipeline, the built-in packs as they ship (every sheet slices, every sound is the pack's own, the named frames are inside their sheets, a pack's own impact frame moves the self-test timetable, the rescue hands over at the kick's size and foot line, no frame ships on a field of paint or with a surface half keyed out of it, the tint stays readable), the launch decision, the onboarding state, every introduction step fitting the one height its window opens at and every state of the window fitting the one height it reserves, the sound switch, the permission switch, its effective state and its evidence-based wait for macOS's own prompt, the ring-fallback offer, the character previews, the self-test's timetable, trace judgement, checkpoints, capture timing and capture comparison, and the packaging inputs and the assembled bundle (version, icon, menu bar template, plist, packs folder).
- `docs/adr/` records the decisions that are hard to reverse; `docs/method/` preserves testing and domain-documentation rules; `docs/artwork.md` describes media provenance; `Tests/Fixtures/ShowReferences/` holds self-test references; `AGENTS.md` is the agent memory.
