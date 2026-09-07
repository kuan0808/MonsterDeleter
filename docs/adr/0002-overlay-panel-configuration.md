# The overlay is an NSPanel with one fixed configuration, mouse events toggled per phase

The show must draw over every Space and full-screen app, on any screen, without stealing the
user's window management, and must be click-through except while aiming and asking. SwiftUI has
no window that can do this, so `OverlayPanel` is an AppKit bridge with exactly the configuration
the Phase 1 spike verified on macOS 26, one panel per screen:

- `styleMask = [.borderless, .nonactivatingPanel]`, `level = .screenSaver`, `isOpaque = false`,
  `backgroundColor = .clear`, `hasShadow = false`,
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`,
  `canBecomeKey = true`, `hidesOnDeactivate = false`, `isReleasedWhenClosed = false`.
- The content view accepts first mouse; without it the click outside during the ask is swallowed.
- `ignoresMouseEvents` is `true` in every phase except aiming and asking (plan decision 7).
- Entering an interactive phase re-keys the panel, makes the content view first responder and
  activates the app, because a click-through phase lets another app take key and Esc would go
  there. Focus is handed back when the show ends, only if nothing else took it meanwhile and the
  previous app has a window on the current Space.
- Esc is handled in `keyDown` (key code 53) and `cancelOperation`; no global key monitor, which
  would need Input Monitoring.

## Why not the alternatives

- `CGShieldingWindowLevel()` and any level above 8 cover TCC prompts equally; `.screenSaver`
  stays because it sits above menus and status items, not because it spares dialogs. The rule
  that follows is that no prompt may be needed while the panel is interactive; the Services path
  never prompts because Finder's pasteboard carries access to the selection.
- A global key monitor for Esc needs Input Monitoring; a key panel does not.
- Changing `level` or `collectionBehavior` between phases is not needed; only
  `ignoresMouseEvents` and key status change.
