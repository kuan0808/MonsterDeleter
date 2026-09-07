# The user-facing surface: an introduction in the app window, preferences in Settings, a guide in the app

Everything written for this app was for its developers. It now has to be usable by someone who has
never seen it, and macOS has settled conventions for where each part of that lives, so we follow
them rather than inventing a shape.

- **The introduction is the first state of the app's one window**, not a sheet and not a separate
  scene. A sheet has to hang off a window - ours would be the window it covers - and a modal
  swallows Esc and cannot be left open beside Finder while the user tries the menu item. Three
  screens: what it does, how to summon it from Finder, and the aiming permission. It opens by itself
  until it is finished or skipped, and **Show the introduction again** brings it back.
- **Everything switchable is in the Settings window on ⌘,** (`Settings` scene, opened from the menu
  bar item with `SettingsLink`): the character, installing one from a zip, where the monster aims,
  and the sound. The character list and the aiming toggle left the menu bar item, because two places
  that can disagree is worse than one place to look.
- **The menu bar item is the way back**: open the window, play a demo, open Settings, quit. The demo
  stays because it is how someone plays a first show without hunting for the Finder entry.
- **The guide is a sheet in the app**, not a document: it is where someone who has installed the app
  looks, and it works offline. The README carries a short version for people who have only found the
  source.
- **Teach with pictures.** The Finder context menu, and what the aiming permission buys, are drawn
  in SwiftUI from system materials and SF Symbols (`ServicesMenuArt`, `AimingArt`) rather than
  screenshotted: a screenshot rots at the next macOS restyle and is wrong in one of the two
  appearances. Text is the caption, not the lesson.
- **The switch shows what is true, not what was asked for.** The aiming toggle reflects the
  effective state - the wish AND the grant - so it reads off while macOS has not granted the
  permission, and the row under it says what is missing, offers the exact pane, and offers to
  withdraw the request. The wish itself is remembered, so the switch turns itself on the moment the
  grant arrives, here or in System Settings, and back off if it is taken away. A control that reads
  on while the behaviour it names is not happening claims a capability the app does not have; this
  is the same honesty rule ADR 0007 applied to pack failures.
- **The permission is asked for the way Apple asks.** One control: turning the switch on is the
  request, and macOS raises its own prompt. The app never asks at launch or during a show, never
  opens System Settings by itself, and only offers the Accessibility pane while the wish is stored
  and the grant is missing, beside a "Stop Asking" button that withdraws the wish - macOS shows its
  prompt once per app, so that pane is what a user who dismissed it needs, and with the switch now
  reading off in that state, withdrawing is what the switch itself can no longer do. The app's own
  explaining alert is gone; the explanation is inline under the switch, and the status is read fresh
  so granting it while the app runs needs no relaunch.
- **The window reserves one height for every state it can be in.** It is sized from its content and
  does not grow when that content changes underneath it, and two of its states appear in a window
  already open on a shorter one: **Show the introduction again**, and the aiming offer a show ending
  in a ring raises. So the window reserves the height of the tallest of them
  (`LandingView.contentHeight`) and the shorter states sit in it with room to spare. Blank space in
  two states is the price of never drawing a state through the buttons at the foot of the window.
- **Permission waiting requires identifiable focus evidence.** The initial request displays
  "Waiting for macOS…" for up to three seconds, allowing the system dialog helper to launch and
  take focus without announcing a refusal before it can appear. Waiting for an answer requires
  both the app resigning active and the frontmost application identifying itself as
  `com.apple.accessibility.universalAccessAuthWarn`, the Accessibility helper on macOS 26.
  Resignation alone is ambiguous: switching to Finder does not qualify. The request must begin
  while the app is active and before the helper owns focus. Missing resignation, no prompt,
  inactive requests, unknown helpers and observations after the detection window all settle to
  the ordinary missing-permission row. An OS change that obscures the helper therefore offers
  the pane instead of assuming a dialog exists. No once-per-app allowance is remembered.
- **Both permission surfaces show the same interval.** After detection they say "Waiting for your
  answer in macOS…". A grant ends waiting even without returning to the app; a genuine return,
  opening the pane or withdrawing the wish also ends it. The shared `AppActivation` tracks every
  self-activation caller, including the show and Trash-failure alert. Its pending request is
  consumed by the activation event, not aged out by a short timer. If macOS never delivers that
  event, a later return is conservatively ignored rather than falsely counted as an answer.
  Ten minutes without a settlement signal abandons waiting even with no screen watching; this
  backstop is for an abandoned interaction, not a deadline for reading the dialog. Waiting is
  never persisted. The shared request boundary checks the director's running state and neither
  prompts during a show nor queues a prompt to appear after it.
- **The two facts that matter during a show are on the show.** A fixed caption under the ask
  buttons, which no character pack can overwrite, says the file goes to the Trash and that Esc
  cancels. A guide nobody has opened is not where safety belongs.

## Consequences

- The app window is no longer "the landing window with a pack picker and a drop zone"; both moved to
  Settings. `CONTEXT.md` follows.
- The self-test's `point` checkpoint now includes the caption under the buttons, so its reference
  was regenerated with the change.

## Controls kept internal

| Control | Owner and reason it stays out of Settings |
|---|---|
| Onboarding completion, Finder-use history and the dismissed aiming offer | `Onboarding` records what happened, not a preference. Finish, Skip, Show the introduction again and Dismiss already provide the relevant user actions. |
| Character sheet grids, frame ranges, impact frame, dimensions, tint, texts and per-sound volumes | The character author owns these in the manifest. They must agree with the artwork and timing; independent user sliders could break a show. The gallery and one sound switch are the user choices. |
| Choreography timing, explosion fan geometry and the maximum drawn hits | These form one tested show, including exact icon centres and all-target Trash behavior. They are not alternate user modes. |
| Target sample age, icon-read budget, traversal depth, messaging timeout and cache sizing | Bounded platform work and performance safeguards, not precision preferences. The aiming switch is the supported choice. |
| Permission detection and abandonment windows | These govern evidence and observation lifetime, not user consent. macOS owns permission; neither timeout grants it or changes the stored wish. |
| `MONSTER_AUTOPLAY` and its point, delay, answer, character, snapshot, reference and repeat options | Maintainer evidence and deterministic self-test inputs that operate on scratch targets. Play Demo is the user entry point. |
| `MONSTER_EXPORT_PLACEHOLDER` | An authoring template export, not a selectable character or a recovery fallback. |
| `CODESIGN_IDENTITY`, `PACKAGE_DMG`, `NOTARY_PROFILE` and icon/art rendering parameters | Build, signing, distribution and artwork tools. They have no meaning as runtime user preferences. |
| Appearance, text size, reduced motion and the Accessibility grant | macOS owns these system choices. The app must respect them rather than introduce competing switches. |
