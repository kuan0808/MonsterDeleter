import AppKit
import MonsterDeleterKit
import SwiftUI

/// The menu bar item, the app's one window and the Settings window. The app has no Dock icon
/// (`LSUIElement`); the Finder Services item, this menu and the windows it opens are its only
/// entry points.
struct MenuBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenu(playDemo: delegate.playDemo, activate: delegate.activation.activate)
    } label: {
      // The bundle has no asset catalog, so the image comes through AppKit (`MenuBarIcon`); macOS
      // tints the template silhouette itself in a light, dark or wallpaper-tinted bar.
      Image(nsImage: MenuBarIcon.image)
        .accessibilityLabel("MonsterDeleter")
    }
    Window("MonsterDeleter", id: LandingView.windowID) {
      LandingView(
        library: delegate.library,
        onboarding: delegate.onboarding,
        iconAiming: delegate.iconAiming,
        playDemo: delegate.playDemo
      )
    }
    .windowResizability(.contentSize)
    .defaultLaunchBehavior(delegate.opensLandingWindow ? .presented : .suppressed)
    Settings {
      SettingsView(library: delegate.library, iconAiming: delegate.iconAiming, sound: delegate.sound)
    }
  }
}

/// The menu's items: the window, the demo, the settings and quit. Nothing switchable lives here -
/// macOS keeps preferences in the Settings window, and a second copy in the menu would be a second
/// place to disagree with it. The demo stays because it is how someone plays their first show
/// without hunting for the Finder entry.
private struct MenuBarMenu: View {
  let playDemo: () -> Void
  /// Through `AppActivation`, so the window coming forward is never mistaken for the user
  /// answering macOS's permission dialog.
  let activate: @MainActor () -> Void
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open MonsterDeleter") {
      openWindow(id: LandingView.windowID)
      activate()
    }
    .keyboardShortcut("o")
    Button("Play Demo", action: playDemo)
      .keyboardShortcut("d")
    Divider()
    SettingsLink {
      Text("Settings…")
    }
    .keyboardShortcut(",")
    Divider()
    Button("Quit MonsterDeleter") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }
}
