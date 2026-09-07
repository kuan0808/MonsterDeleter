# MonsterDeleter

A macOS menu bar app that plays a short animated show over the desktop and moves one Finder
selection, files and folders alike, to the Trash at the show's impact frame.

## Language

**Show**:
One run of the choreography for one selection, from summon to done or cancelled: one walk, one
ask, one kick, one explosion fan.
_Avoid_: animation, session

**Summon**:
Starting a show for a target, from the Finder Services item, the demo menu item or autoplay.
_Avoid_: invoke, trigger, launch

**Selection**:
The files and folders one summon delivers, sorted by path so Finder's unreliable order never
shows; every item is a target of the same show.
_Avoid_: batch, items, URLs

**Target**:
One file or folder of the selection; the show treats folders exactly like files.
_Avoid_: victim, file (when a folder is possible)

**Target point**:
The screen position the monster walks to and the explosion is centred on, in AppKit global
coordinates; comes from the target's icon rect, from the last right-click or from the crosshair.
_Avoid_: mouse location, click position

**Target aim**:
Where one show aims: its target point, the icon rects icon aiming resolved for the selection on
one screen, and the point the targets it could not resolve are fanned around. A summon without
one starts with the crosshair.
_Avoid_: aim point, target info

**Icon rect**:
The rectangle Finder draws one target's icon in, read from its accessibility tree while a show is
being summoned and converted to AppKit global coordinates. The monster stands clear of it and the
target's own explosion is centred on it.
_Avoid_: icon frame, bounds, position

**Icon aiming**:
Reading the icon rects out of Finder: a preference, off until the user turns it on, and only ever
with the Accessibility permission. The preference is the user's remembered wish; the switch shows
the effective state, the wish AND the grant, so it reads off while macOS has not granted the
permission and turns itself on the moment the grant arrives. Off, refused, or slower than its
budget, the show falls back to the right-click and then to the crosshair, silently and per target.
_Avoid_: accessibility mode, precise targeting

**Explosion fan**:
The explosion centres of a selection, one per target: a target with an icon rect explodes on that
rect's centre exactly, the rest are fanned a fixed rise above the target aim's fan centre - alone
on that point, two to six ringed around it, from seven on the point plus rings - up to 19 drawn
hits however large the selection is. A fan of two or more is kept inside the screen; an explosion
on an icon never is, nor is a lone one, and the panel clips them.
_Avoid_: spread, scatter, cluster

**Unaimed fan**:
A show of two or more targets that ran to the end without one icon rect resolved, so every
explosion landed in the ring around the click (`UnaimedFan`). The landing window offers icon
aiming after one, dismissibly; a cancelled show, or one that never ran, is not one.
_Avoid_: failed aiming, ring mode

**Crosshair**:
The aiming phase: every screen dims and the user clicks the target themselves. Fallback only.
_Avoid_: targeting mode, reticle

**Phase**:
One step of the show, in order: aiming, entering, walking, asking, kicking, exploding, rescuing,
flying, done; plus cancelled. Aiming and asking are interactive; the rest are click-through.
_Avoid_: state, step, stage

**Choreography**:
The timing and layout constants of the show (frame rate, durations, offsets, easings), shared by
every pack.
_Avoid_: timeline, config

**Character pack**:
One set of six sheets, three sounds and the ask texts that dress the choreography, described by
a manifest; whatever a pack leaves out comes from the placeholder.
_Avoid_: theme, skin, character set

**Manifest**:
A pack's `pack.json`: every field optional, the built-in defaults filling the rest, a malformed
value replaced by its default with a warning.
_Avoid_: config, descriptor (for the file; the decoded value is the descriptor)

**Built-in pack**:
A pack shipped in the app bundle: the folders under `Packaging/packs/`, currently Kaiju, Cat and
UFO. The generated placeholder is not one of them - it is not a pack anyone can choose
(`docs/adr/0007-no-placeholder-fallback.md`).
_Avoid_: bundled pack, system pack

**User pack**:
A pack installed under `~/Library/Application Support/MonsterDeleter/packs/` from a zip dropped on
the settings window.
_Avoid_: custom pack, third-party pack

**Pack library**:
The built-in and user packs the app knows about and the chosen one, persisted across launches once
it has loaded. A pack that cannot be loaded is reported by name and never replaced by the
placeholder; with none that load the app wears nothing and plays no show.
_Avoid_: pack manager, catalogue

**First-run pack**:
The pack a fresh install wears when nothing has been chosen: Kaiju, or the first pack in the list
when the bundle has no Kaiju. Not written to the saved choice, so the saved choice keeps meaning
what the user picked.
_Avoid_: default pack, initial pack

**Slicing cache**:
Per-pack copies of the sheets scaled so each frame is twice its displayed height, under
Application Support, replaced when a sheet file's modification date changes.
_Avoid_: frame cache, thumbnails

**Swap**:
Dressing a running show in the next pack during the ask: frames, sounds and texts change, the
phase and its timing do not.
_Avoid_: switch (that is choosing in the Settings window), hot reload

**Tint**:
A pack's optional colour for the bubble and the buttons.
_Avoid_: theme colour, accent

**Landing window**:
The app's one window (`LandingView`): the onboarding until it is done, and the home screen after -
what the app is, how to summon it, the demo, the guide and the way into the settings window.
_Avoid_: main window, settings, preferences

**Onboarding**:
The three screens a fresh install opens on: what the app does, where the Finder Services item is,
and the offer of icon aiming. Skippable, shown until finished or skipped, and available again from
the landing window.
_Avoid_: tutorial, welcome, first-run wizard

**Settings window**:
The standard macOS settings scene on Cmd-comma, and the only place anything switchable lives: the
character, installing one from a zip, icon aiming and the sound.
_Avoid_: preferences pane, options, landing window (that is the other window)

**Guide**:
The nine answers a user may need, as a sheet over the landing window; the README carries a short
version for people reading the source instead.
_Avoid_: help, documentation, manual

**Sound**:
Whether a show may play its pack's three sounds at all: one switch in the settings window, on
unless the user turns it off.
_Avoid_: mute, volume, audio settings

**Sheet**:
One sprite sheet of a pack, a grid of frames (5 x 3 unless its manifest entry declares another),
for one role: walk, point, kick, explosion, rescuer, fly.
_Avoid_: spritesheet, atlas, animation

**Frame**:
One cell of a sheet, shown for one frame duration (125 ms at 8 fps).
_Avoid_: sprite, cell

**Rescuer**:
The second character that enters after the kick and flies out with the monster.
_Avoid_: Leo, hero, sidekick

**Seed still**:
The generated image a motion clip starts from, holding one pose of a sheet's first frame. It
passes the locked character designs to the model as references, so a clip reproduces the figure
rather than re-inventing it.
_Avoid_: keyframe, reference image (that is what the seed itself is given)

**Motion clip**:
The short generated video one sheet is cut out of, by `scripts/pack-sheet.sh`.
_Avoid_: animation, take, footage

**Backdrop matte**:
The alpha pulled off a motion clip's flat magenta backdrop by measuring it in every frame
(`scripts/lib/backdrop-matte.py`), rather than keying one fixed colour.
_Avoid_: chroma key, green screen, background removal

**Overlay panel**:
The transparent per-screen window the show is drawn in.
_Avoid_: overlay window, HUD

**Trash**:
Moving the whole selection to the Trash in one `NSWorkspace.recycle` call at the impact frame,
reporting each item's result. Finder owns restoration. Never a permanent delete.
_Avoid_: delete, remove, destroy

**Personal build**:
The app built and signed on the developer's Mac, ad hoc or with a personal-team identity; it runs
here without Gatekeeper because it was never quarantined.
_Avoid_: dev build, local build

**Public build**:
The same bundle signed with Developer ID, notarized and stapled by `scripts/notarize.sh`, fit
for another Mac.
_Avoid_: release build, distribution build

**Release artifact**:
The zip (and optional DMG) of a signed bundle that `scripts/package.sh` writes under `build/`,
named after the version in `Packaging/Info.plist`.
_Avoid_: installer, package (the pack is something else)

**Self-test**:
One `MONSTER_AUTOPLAY` run judged by the app itself: every event against the timetable, the
selection in the Trash or untouched after Esc, every checkpoint against its reference; exit
status non-zero on any miss. `scripts/self-test.sh` plays a confirmed show and an Esc show.
_Avoid_: smoke test, integration test, autoplay (that is the mechanism, not the verdict)

**Timetable**:
The events one show must report in order, each with the gap the choreography promises after the
one before; only the answer to the ask carries slack.
_Avoid_: schedule, expected trace

**Checkpoint**:
One of six moments of a show captured to PNG by the self-test, one per sheet (walk, point,
kick, explosion, rescuer, fly), each a fixed number of frame slots into its phase, as a
640 x 520 pt window centred on the target point.
_Avoid_: screenshot, snapshot (that is the mechanism), keyframe

**Reference**:
The committed PNG a checkpoint is compared with, under `Tests/Fixtures/ShowReferences/`;
regenerated only by `scripts/self-test.sh --update-references`.
_Avoid_: golden image, baseline

**Trash failure notice**:
The one notification after the show that names the targets that stayed put and why: the first
five with their reason, then a count of the rest.
_Avoid_: error dialog, alert (it is only the fallback)
