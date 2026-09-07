import AppKit

/// AppKit bridge. The app bringing itself in front, and whether it has just done so. macOS gives
/// no way to tell an activation the user caused from one the app asked for, and the difference
/// matters: a screen waiting for the user to answer macOS's own Accessibility dialog must not read
/// the alert the app pulled itself forward for as that answer.
///
/// Every `NSApp.activate()` in the app goes through here, so "the app did this" is recorded in one
/// place rather than guessed at the point it is read.
@MainActor
public final class AppActivation {
  private var pendingSelfActivation = false
  private let isAppActive: @MainActor () -> Bool
  private let activateApp: @MainActor () -> Void

  /// The activation is a parameter so a test can watch what the app asked for without a window
  /// coming forward.
  public init(
    activateApp: @escaping @MainActor () -> Void = { NSApp.activate() },
    isAppActive: @escaping @MainActor () -> Bool = { NSApp?.isActive == true }
  ) {
    self.activateApp = activateApp
    self.isAppActive = isAppActive
  }

  /// Brings the app in front, and records that the app did it rather than the user.
  public func activate() {
    if !isAppActive() { pendingSelfActivation = true }
    activateApp()
  }

  /// An app-requested activation stays pending until delivered, even if macOS delays it.
  public func consumeSelfActivation() -> Bool {
    defer { pendingSelfActivation = false }
    return pendingSelfActivation
  }
}
