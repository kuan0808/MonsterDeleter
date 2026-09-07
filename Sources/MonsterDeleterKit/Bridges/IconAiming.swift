import AppKit
import ApplicationServices
import Observation

/// AppKit bridge. Whether the show aims at the Finder icon, and the one place the Accessibility
/// permission is ever asked for. SwiftUI has no API for the permission, for macOS's own prompt, or
/// for opening a System Settings pane.
///
/// One switch, one intent: turning the preference on is the request, and macOS puts its own prompt
/// up. The app never asks at launch or during a show - the overlay panel sits above every prompt,
/// so one raised mid-show would be unreachable (`docs/adr/0002-overlay-panel-configuration.md`) -
/// and it never opens System Settings on its own. The permission lifecycle and recovery controls
/// are defined in `docs/adr/0008-user-facing-surface.md`.
@MainActor
@Observable
public final class IconAiming {
  public static let preferenceKey = "aimsAtFinderIcons"

  /// Allows macOS to launch its Accessibility dialog helper and transfer focus. This is a
  /// detection window, not an answer deadline: no resignation, another app taking focus, an
  /// inactive request or a late observation leaves the ordinary needs-permission state.
  static let promptWindow: Duration = .seconds(3)
  static let abandonmentWindow: Duration = .seconds(600)

  /// Whether the user wants the monster to walk to the icon rather than to the right-click.
  public private(set) var isEnabled: Bool

  /// Whether macOS has granted the Accessibility permission, as the screens that show its status
  /// last read it. `watchTrust()` keeps it current while such a screen is up.
  public private(set) var isTrusted: Bool

  /// macOS's own permission dialog is up and unanswered, so the screens hold still rather than
  /// telling the user the permission is missing while the question sits in front of them.
  ///
  /// Only a resignation followed by focus on macOS's Accessibility dialog helper within
  /// `promptWindow` establishes a wait. Ambiguous or unobserved focus changes settle to the pane.
  /// Grant, genuine return or a row action settles it; ten minutes without any of these means
  /// abandonment, including an app that never regains focus. No waiting state is persisted.
  public private(set) var isWaitingForAnswer = false
  public private(set) var isRequestingPermission = false
  public var showIsRunning: @MainActor () -> Bool = { false }

  private let reader = FinderIconReader()
  private let defaults: UserDefaults
  private let prompt: @MainActor () -> Bool
  private let trusted: @MainActor () -> Bool
  private let openURL: @MainActor (URL) -> Void
  private let activation: AppActivation
  private let isAppActive: @MainActor () -> Bool
  private let promptOwnsFocus: @MainActor () -> Bool
  private let now: @MainActor () -> ContinuousClock.Instant
  private var observedResignation = false
  private var waitTask: Task<Void, Never>?
  /// When the permission was last asked for, or `nil` when no answer is outstanding.
  private var requestedAt: ContinuousClock.Instant?
  static let accessibilityPane = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  )

  /// The system calls are parameters so a test can watch what the switch does without macOS
  /// putting its own prompt up or opening a window.
  public init(
    defaults: UserDefaults = .standard,
    // `kAXTrustedCheckOptionPrompt` is imported as a mutable global, which Swift 6 will not let
    // a concurrent program read; its value is this string.
    prompt: @escaping @MainActor () -> Bool = {
      AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    },
    trusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
    openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
    activation: AppActivation = AppActivation(),
    isAppActive: @escaping @MainActor () -> Bool = { NSApp?.isActive == true },
    promptOwnsFocus: @escaping @MainActor () -> Bool = {
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.accessibility.universalAccessAuthWarn"
    },
    now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
  ) {
    self.defaults = defaults
    self.prompt = prompt
    self.trusted = trusted
    self.openURL = openURL
    self.activation = activation
    self.isAppActive = isAppActive
    self.promptOwnsFocus = promptOwnsFocus
    self.now = now
    isEnabled = defaults.bool(forKey: Self.preferenceKey)
    isTrusted = trusted()
  }

  /// Re-reads the grant every `interval` for as long as the task running this is alive, so a
  /// permission given in System Settings while a screen shows its status needs no relaunch. The
  /// one place that polling lives, for both the settings row and the introduction's third step.
  /// Nothing is asked of macOS while icon aiming is off, since no screen shows the status then.
  public func watchTrust(interval: Duration = .seconds(1)) async {
    while !Task.isCancelled {
      if isEnabled {
        refreshTrust()
      }
      try? await Task.sleep(for: interval)
    }
  }

  /// Reads the grant again, and writes it only when it has changed: `@Observable` invalidates
  /// every reader on assignment, and this runs once a second for as long as a screen is up.
  private func refreshTrust() {
    let granted = trusted()
    if granted != isTrusted { isTrusted = granted }
    if granted { stopWaiting() }
  }

  /// Resignation is necessary but not sufficient: the dialog helper must also take focus.
  public func appResignedActive() {
    guard isRequestingPermission else { return }
    observedResignation = true
    _ = checkRequest()
  }

  /// The app has the focus again, so the dialog has gone: the wait ends whatever was answered, and
  /// the grant is read to find out which it was. An activation the app asked for itself - the
  /// alert a failed pack load raises, the menu bar item opening the window - answers nothing, so
  /// it leaves the wait alone (`AppActivation`).
  public func appBecameActive() {
    let selfActivation = activation.consumeSelfActivation()
    refreshTrust()
    guard !selfActivation else { return }
    stopWaiting()
  }

  private func stopWaiting() {
    setWaiting(false)
    setRequesting(false)
    requestedAt = nil
    observedResignation = false
    waitTask?.cancel()
    waitTask = nil
  }

  private func setWaiting(_ waiting: Bool) {
    guard waiting != isWaitingForAnswer else { return }
    isWaitingForAnswer = waiting
  }

  private func setRequesting(_ requesting: Bool) {
    guard requesting != isRequestingPermission else { return }
    isRequestingPermission = requesting
  }

  private func checkRequest() -> Bool {
    refreshTrust()
    guard let requestedAt else { return false }
    let elapsed = requestedAt.duration(to: now())
    if elapsed >= (isWaitingForAnswer ? Self.abandonmentWindow : Self.promptWindow) {
      stopWaiting()
      return false
    }
    if isRequestingPermission, observedResignation, promptOwnsFocus() {
      setWaiting(true)
      setRequesting(false)
    }
    return true
  }

  private func watchForTheDialog() {
    waitTask = Task { [weak self] in
      while !Task.isCancelled, self?.checkRequest() == true {
        let interval: Duration = self?.isWaitingForAnswer == true ? .seconds(1) : .milliseconds(50)
        do {
          try await Task.sleep(for: interval)
        } catch {
          return
        }
      }
    }
  }

  /// What the switch shows: the wish AND the grant, which is the only state that is true. A
  /// control that reads on while the behaviour it names is not happening claims a capability the
  /// app does not have, and teaches the user that the control means nothing - the same dishonesty
  /// `docs/adr/0007-no-placeholder-fallback.md` took out of pack failures.
  public var isActive: Bool { isEnabled && isTrusted }

  /// The user asked for icon aiming and macOS has not granted it: the show still runs, aiming at
  /// the right-click, the switch stays off because that is the truth, and the row says what is
  /// missing, offers the pane, and offers to withdraw the request. Suppressed during prompt
  /// detection and the evidence-based wait for an answer (`isWaitingForAnswer`).
  public var needsPermission: Bool {
    isEnabled && !isTrusted && !isWaitingForAnswer && !isRequestingPermission
  }

  /// Where a summon reads the icons from, or `nil` when the preference is off or the permission
  /// is missing, which is what makes the tier fall silently to the right-click.
  public var iconRects: (any IconRectSource)? {
    isEnabled && trusted() ? reader : nil
  }

  /// The switch. Turning it on is the request: macOS raises its own prompt when it still can, and
  /// the wish is remembered even when the grant never comes, so `isActive` turns over by itself
  /// the moment the permission arrives - here or in System Settings, with no second visit to the
  /// row and no relaunch.
  public func setEnabled(_ enabled: Bool) {
    if isEnabled != enabled { isEnabled = enabled }
    defaults.set(enabled, forKey: Self.preferenceKey)
    refreshTrust()
    stopWaiting()
    guard enabled, !isTrusted, !showIsRunning() else { return }
    if isAppActive(), !promptOwnsFocus() {
      requestedAt = now()
      setRequesting(true)
      watchForTheDialog()
    }
    _ = prompt()
    refreshTrust()
  }

  /// "Open Accessibility Settings…", offered only while `needsPermission`: macOS shows its prompt
  /// once per app, so a user who dismissed it needs the pane itself, and it opens that pane rather
  /// than the top of System Settings.
  public func openAccessibilitySettings() {
    stopWaiting()
    guard let pane = Self.accessibilityPane else { return }
    openURL(pane)
  }
}
