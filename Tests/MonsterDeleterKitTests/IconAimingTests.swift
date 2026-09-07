import Foundation
import Observation
import Synchronization
import Testing

@testable import MonsterDeleterKit

/// One switch, one intent: turning icon aiming on is the request for the permission, and the way
/// to the Accessibility pane only exists while macOS has not granted it. The two system calls are
/// stubbed, so no test here asks macOS for the permission or opens a window.
@MainActor
@Suite("Icon aiming permission")
struct IconAimingTests {
  /// Collects what the app asked the system for. A class because the stubs outlive the call.
  final class SystemCalls {
    var prompts = 0
    var openedPanes: [URL] = []
    /// The grant, as macOS would answer it now. A test moves it the way the user would in System
    /// Settings while the app is running.
    var isTrusted = false
    var trustChecks = 0
    var isAppActive = false
    var promptOwnsFocus = false
    var showIsRunning = false
    var now = ContinuousClock.now
  }

  func aiming(trusted: Bool, calls: SystemCalls, activation: AppActivation? = nil) -> IconAiming {
    calls.isTrusted = trusted
    let aiming = IconAiming(
      defaults: UserDefaults(suiteName: "MonsterDeleterTests-\(UUID().uuidString)")!,
      prompt: {
        calls.prompts += 1
        return calls.isTrusted
      },
      trusted: {
        calls.trustChecks += 1
        return calls.isTrusted
      },
      openURL: { calls.openedPanes.append($0) },
      activation: activation ?? AppActivation(activateApp: {}, isAppActive: { false }),
      isAppActive: { calls.isAppActive },
      promptOwnsFocus: { calls.promptOwnsFocus },
      now: { calls.now }
    )
    aiming.showIsRunning = { calls.showIsRunning }
    return aiming
  }

  @Test("turning the switch on lets macOS ask for the permission")
  func turningOnAsks() {
    let calls = SystemCalls()
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    #expect(aiming.isEnabled)
    #expect(calls.prompts == 1)
    #expect(calls.openedPanes.isEmpty, "the app never opens System Settings on its own")
  }

  @Test("with the permission already granted the switch just turns it on")
  func turningOnWhenTrusted() {
    let calls = SystemCalls()
    let aiming = aiming(trusted: true, calls: calls)
    aiming.setEnabled(true)
    #expect(calls.prompts == 0)
    #expect(!aiming.needsPermission)
  }

  @Test("turning it off asks for nothing")
  func turningOff() {
    let calls = SystemCalls()
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(false)
    #expect(calls.prompts == 0)
    #expect(!aiming.needsPermission, "nothing is missing while the user has not asked for aiming")
  }

  @Test("the way to the Accessibility pane is offered only while the permission is missing")
  func needsPermission() {
    let calls = SystemCalls()
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    #expect(aiming.needsPermission)
    aiming.openAccessibilitySettings()
    #expect(
      calls.openedPanes.map(\.absoluteString) == [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      ],
      "the exact pane, not the top of System Settings"
    )
  }

  @Test("a grant made while the screen shows the status turns it over, and the watch stops with the screen")
  func watchingTheGrant() async throws {
    let calls = SystemCalls()
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    #expect(aiming.needsPermission)
    let watching = Task { await aiming.watchTrust(interval: .milliseconds(5)) }
    calls.isTrusted = true
    try await until(.milliseconds(5)) { aiming.isTrusted }
    #expect(aiming.isTrusted, "the grant arrived while the screen was showing the status")
    #expect(!aiming.needsPermission, "so the screen stops asking for it, without a relaunch")
    watching.cancel()
    _ = await watching.value
    calls.isTrusted = false
    let afterTheScreen = calls.trustChecks
    try await Task.sleep(for: .milliseconds(30))
    #expect(calls.trustChecks == afterTheScreen, "nothing polls once the screen has gone")
    #expect(aiming.isTrusted)
  }

  @Test("nothing asks macOS about the permission while icon aiming is off")
  func watchingIsIdleWhileOff() async throws {
    let calls = SystemCalls()
    let aiming = aiming(trusted: false, calls: calls)
    let atStart = calls.trustChecks
    let watching = Task { await aiming.watchTrust(interval: .milliseconds(5)) }
    try await Task.sleep(for: .milliseconds(40))
    let whileOff = calls.trustChecks
    aiming.setEnabled(true)
    calls.isTrusted = true
    try await until(.milliseconds(5)) { aiming.isTrusted }
    watching.cancel()
    _ = await watching.value
    #expect(whileOff == atStart, "the switch is off, so no screen is showing the grant")
    #expect(aiming.isTrusted, "turning the switch on while the screen is up starts reading it")
  }

  @Test("the switch shows what is true: asked for is not on, granted is, revoked is not again")
  func switchShowsTheEffectiveState() async throws {
    let calls = SystemCalls()
    let aiming = aiming(trusted: false, calls: calls)

    aiming.setEnabled(true)
    #expect(!aiming.isActive, "the permission is missing, so the switch must not claim the app aims at icons")
    #expect(aiming.isEnabled, "the wish is remembered even though it is not in effect")
    #expect(aiming.needsPermission, "and the row says what is missing")

    let watching = Task { await aiming.watchTrust(interval: .milliseconds(5)) }
    calls.isTrusted = true
    try await until(.milliseconds(5)) { aiming.isActive }
    #expect(aiming.isActive, "the grant arrived while the window was open, so the switch turns itself on")
    #expect(!aiming.needsPermission, "and nothing is missing any more")

    calls.isTrusted = false
    try await until(.milliseconds(5)) { !aiming.isActive }
    #expect(!aiming.isActive, "the permission was taken away outside the app, so the switch goes back off")
    #expect(aiming.isEnabled, "the wish outlives the grant")
    watching.cancel()
    _ = await watching.value
  }

  @Test("a wish the permission never answered survives a relaunch and stays off until it is granted")
  func theWishOutlivesTheLaunch() {
    let calls = SystemCalls()
    let suite = "MonsterDeleterTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let asked = IconAiming(defaults: defaults, prompt: { false }, trusted: { calls.isTrusted }, openURL: { _ in })
    asked.setEnabled(true)
    #expect(!asked.isActive)

    let relaunched = IconAiming(defaults: defaults, prompt: { false }, trusted: { calls.isTrusted }, openURL: { _ in })
    #expect(relaunched.isEnabled, "the app remembers what the user asked for")
    #expect(!relaunched.isActive, "and still does not claim to be doing it")
    calls.isTrusted = true
    let granted = IconAiming(defaults: defaults, prompt: { false }, trusted: { calls.isTrusted }, openURL: { _ in })
    #expect(granted.isActive, "with the grant in place the remembered wish is in effect, with nothing to press")
  }

  /// Polls `condition` at `interval` until it holds or a second has gone by, which is what a
  /// screen showing the grant does while the user is away in System Settings.
  private func until(_ interval: Duration, _ condition: () -> Bool) async throws {
    var ticks = 0
    while !condition(), ticks < 200 {
      try await Task.sleep(for: interval)
      ticks += 1
    }
  }

  // MARK: Waiting for macOS's own dialog

  @Test("nothing waits on a request that raised no dialog: the row says the permission is missing")
  func noDialogMeansNoWait() {
    let calls = SystemCalls()
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    #expect(calls.prompts == 1, "macOS was asked")
    #expect(!aiming.isWaitingForAnswer, "but it shows its prompt once per app, so there may be none")
    #expect(aiming.needsPermission, "and with no dialog to answer the pane is what the user needs")
  }

  @Test("losing the focus with nothing asked for is not a permission dialog")
  func focusLostWithNothingOutstanding() {
    let calls = SystemCalls()
    let aiming = aiming(trusted: false, calls: calls)
    aiming.appResignedActive()
    #expect(!aiming.isWaitingForAnswer, "the user went somewhere else; nothing was ever asked")
    calls.isAppActive = true
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    #expect(aiming.isWaitingForAnswer)
    aiming.setEnabled(false)
    aiming.appResignedActive()
    #expect(!aiming.isWaitingForAnswer, "withdrawing the request ends the wait and asks nothing more")
  }

  @Test("while macOS's dialog holds the focus the row asks for nothing beside it")
  func waitingOnTheDialog() {
    let calls = SystemCalls()
    let aiming = aiming(trusted: false, calls: calls)
    calls.isAppActive = true
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    #expect(aiming.isWaitingForAnswer, "the dialog took the focus, which is the evidence it is up")
    #expect(!aiming.needsPermission, "the question is in front of the user; a second ask is noise")
    #expect(!aiming.isActive, "and nothing claims the app is aiming at icons yet")
  }

  @Test("the app pulling itself forward is not the user answering the dialog")
  func selfActivationIsNotAnAnswer() {
    let calls = SystemCalls()
    let activation = AppActivation(activateApp: {}, isAppActive: { false })
    let aiming = aiming(trusted: false, calls: calls, activation: activation)
    calls.isAppActive = true
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    activation.activate()
    aiming.appBecameActive()
    #expect(aiming.isWaitingForAnswer, "the app raised an alert of its own; the dialog is still up")
    #expect(!aiming.needsPermission)
  }

  @Test("the answer ends the wait: granted turns the switch on, denied asks for the pane")
  func theAnswerEndsTheWait() {
    let calls = SystemCalls()
    let granted = aiming(trusted: false, calls: calls)
    calls.isAppActive = true
    granted.setEnabled(true)
    calls.promptOwnsFocus = true
    granted.appResignedActive()
    calls.isTrusted = true
    granted.appBecameActive()
    #expect(!granted.isWaitingForAnswer)
    #expect(granted.isActive, "the user allowed it, so the switch is on with nothing left to press")

    let refused = SystemCalls()
    let denied = aiming(trusted: false, calls: refused)
    refused.isAppActive = true
    denied.setEnabled(true)
    refused.promptOwnsFocus = true
    denied.appResignedActive()
    denied.appBecameActive()
    #expect(!denied.isWaitingForAnswer, "the dialog has gone, so the app stops waiting on it")
    #expect(denied.needsPermission, "and the row offers the pane, which is all that is left")
  }

  @Test("the show reads the icons only when the switch is on and the permission is there")
  func iconSource() {
    let calls = SystemCalls()
    #expect(aiming(trusted: false, calls: calls).iconRects == nil)
    let granted = aiming(trusted: true, calls: calls)
    #expect(granted.iconRects == nil, "the preference is off until the user turns it on")
    granted.setEnabled(true)
    #expect(granted.iconRects != nil)
  }

  @Test("the initial request has a neutral status until prompt detection finishes")
  func initialRequestDoesNotAnnounceFailure() async throws {
    let calls = SystemCalls()
    calls.isAppActive = true
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    #expect(aiming.isRequestingPermission)
    #expect(!aiming.isWaitingForAnswer)
    #expect(!aiming.needsPermission)
    calls.now += .seconds(4)
    try await until(.milliseconds(5)) { aiming.needsPermission }
    #expect(aiming.needsPermission)
    #expect(!aiming.isRequestingPermission)
  }

  @Test(
    "no prompt, ambiguous focus, and late evidence all settle to the ordinary permission row",
    arguments: ["no resignation", "another app", "late resignation", "late observation", "inactive"]
  )
  func unobservablePrompt(kind: String) async throws {
    let calls = SystemCalls()
    calls.isAppActive = kind != "inactive"
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    if kind == "late resignation" || kind == "late observation" { calls.now += .seconds(4) }
    calls.promptOwnsFocus = kind != "another app"
    if kind != "no resignation" { aiming.appResignedActive() }
    #expect(!aiming.isWaitingForAnswer)
    calls.now += .seconds(4)
    try await until(.milliseconds(5)) { aiming.needsPermission }
    #expect(aiming.needsPermission)
    #expect(!aiming.isRequestingPermission)
  }

  @Test("a repeat request followed by switching to Finder cannot start waiting")
  func repeatRequestThenFinder() async throws {
    let calls = SystemCalls()
    calls.isAppActive = true
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    aiming.appBecameActive()
    calls.promptOwnsFocus = false
    aiming.setEnabled(true)
    aiming.appResignedActive()
    #expect(!aiming.isWaitingForAnswer)
    calls.now += .seconds(4)
    try await until(.milliseconds(5)) { aiming.needsPermission }
    #expect(aiming.needsPermission)
    #expect(calls.prompts == 2)
  }

  @Test("a grant ends waiting without returning to the app, and revocation restores the warning")
  func grantWhileAway() async throws {
    let calls = SystemCalls()
    calls.isAppActive = true
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    #expect(aiming.isWaitingForAnswer)
    let watching = Task { await aiming.watchTrust(interval: .milliseconds(5)) }
    defer { watching.cancel() }
    calls.isTrusted = true
    try await until(.milliseconds(5)) { aiming.isActive }
    #expect(aiming.isActive)
    #expect(!aiming.isWaitingForAnswer)
    calls.isTrusted = false
    try await until(.milliseconds(5)) { aiming.needsPermission }
    #expect(aiming.needsPermission)
    #expect(!aiming.isWaitingForAnswer)
  }

  @Test("opening the pane or withdrawing the wish ends waiting")
  func rowActionsSettleWaiting() {
    let calls = SystemCalls()
    calls.isAppActive = true
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    aiming.openAccessibilitySettings()
    #expect(!aiming.isWaitingForAnswer)
    #expect(aiming.needsPermission)
    #expect(calls.openedPanes.count == 1)
    calls.promptOwnsFocus = false
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    aiming.setEnabled(false)
    #expect(!aiming.isWaitingForAnswer)
    #expect(!aiming.isEnabled)
    #expect(!aiming.needsPermission)
  }

  @Test("reading the dialog is not timed out, but a never-returning user cannot strand waiting")
  func abandonedDialog() async throws {
    let calls = SystemCalls()
    calls.isAppActive = true
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    calls.now += .seconds(120)
    await Task.yield()
    #expect(aiming.isWaitingForAnswer)
    calls.now += .seconds(600)
    try await until(.milliseconds(10)) { aiming.needsPermission }
    #expect(!aiming.isWaitingForAnswer)
    #expect(aiming.needsPermission)
  }

  @Test("waiting is interrupted by relaunch while the wish survives")
  func waitingIsNotPersisted() {
    let defaults = UserDefaults(suiteName: "MonsterDeleterTests-\(UUID().uuidString)")!
    let calls = SystemCalls()
    let aiming = IconAiming(
      defaults: defaults,
      prompt: { false },
      trusted: { false },
      isAppActive: { true },
      promptOwnsFocus: { calls.promptOwnsFocus }
    )
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    #expect(aiming.isWaitingForAnswer)
    let relaunched = IconAiming(defaults: defaults, prompt: { false }, trusted: { false })
    #expect(relaunched.isEnabled)
    #expect(relaunched.needsPermission)
    #expect(!relaunched.isWaitingForAnswer)
    #expect(!relaunched.isRequestingPermission)
    aiming.setEnabled(false)
  }

  @Test("an activation request is consumed by its eventual event, never by a short timer")
  func selfActivationIsConsumedOnce() {
    let calls = SystemCalls()
    let activation = AppActivation(activateApp: {}, isAppActive: { calls.isAppActive })
    activation.activate()
    #expect(activation.consumeSelfActivation())
    #expect(!activation.consumeSelfActivation())
    calls.isAppActive = true
    activation.activate()
    #expect(!activation.consumeSelfActivation(), "activating an already active app causes no return event")
  }

  @Test("permission requests are suppressed during a show and are never queued for its end")
  func noPromptDuringShow() async throws {
    let calls = SystemCalls()
    calls.showIsRunning = true
    calls.isAppActive = true
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    #expect(calls.prompts == 0)
    #expect(aiming.needsPermission)
    #expect(!aiming.isRequestingPermission)
    calls.showIsRunning = false
    let watching = Task { await aiming.watchTrust(interval: .milliseconds(5)) }
    try await Task.sleep(for: .milliseconds(20))
    watching.cancel()
    await watching.value
    #expect(calls.prompts == 0)
    aiming.setEnabled(true)
    #expect(calls.prompts == 1)
    aiming.setEnabled(false)
  }
  @Test("the helper taking focus after resignation is observed without another resignation")
  func delayedFocusObservation() async throws {
    let calls = SystemCalls()
    calls.isAppActive = true
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    aiming.appResignedActive()
    #expect(!aiming.isWaitingForAnswer)
    calls.promptOwnsFocus = true
    try await until(.milliseconds(5)) { aiming.isWaitingForAnswer }
    #expect(aiming.isWaitingForAnswer)
    aiming.setEnabled(false)
  }

  @Test("unchanged permission polling does not invalidate observable status")
  func unchangedStatusDoesNotNotify() async throws {
    let calls = SystemCalls()
    calls.isAppActive = true
    let aiming = aiming(trusted: false, calls: calls)
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    let changes = Mutex(0)
    withObservationTracking {
      _ = aiming.isWaitingForAnswer
      _ = aiming.isRequestingPermission
      _ = aiming.isTrusted
      _ = aiming.isEnabled
    } onChange: {
      changes.withLock { $0 += 1 }
    }
    let watching = Task { await aiming.watchTrust(interval: .milliseconds(5)) }
    try await Task.sleep(for: .milliseconds(30))
    watching.cancel()
    await watching.value
    #expect(changes.withLock { $0 } == 0)
    aiming.setEnabled(false)
    #expect(changes.withLock { $0 } == 1)
  }

}
