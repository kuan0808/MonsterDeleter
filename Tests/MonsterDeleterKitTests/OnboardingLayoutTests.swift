import AppKit
import SwiftUI
import Testing

@testable import MonsterDeleterKit

/// The introduction's window is sized from its content and does not grow when the step changes, so
/// every step has to fit in the one height the window opens at. The steps are laid out for real
/// here and measured, which is the only thing that can catch a copy change outgrowing that height:
/// a step that does overflows over the Not Now link, the page dots and the Done button under it.
@MainActor
@Suite("The introduction's steps fit the window")
struct OnboardingLayoutTests {
  init() {
    // The first step falls back to the app icon while no character has loaded, and `NSApp` is nil
    // in a test process until something asks for it.
    _ = NSApplication.shared
  }

  /// The introduction with a stubbed permission, so nothing here asks macOS for the grant, and an
  /// empty library, so the first step draws the app icon rather than a character's own frame - the
  /// picture there sits in a fixed-height row either way.
  func introduction(
    trusted: Bool = false,
    wish: Bool = false,
    summoned: Bool = false,
    waiting: Bool = false,
    requesting: Bool = false
  ) -> OnboardingView {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "OnboardingLayoutTests-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: "OnboardingLayoutTests-\(UUID().uuidString)")!
    let calls = IconAimingTests.SystemCalls()
    let aiming = IconAiming(
      defaults: defaults,
      prompt: { trusted },
      trusted: { trusted },
      openURL: { _ in },
      isAppActive: { waiting || requesting },
      promptOwnsFocus: { calls.promptOwnsFocus }
    )
    if wish || waiting || requesting { aiming.setEnabled(true) }
    if waiting {
      calls.promptOwnsFocus = true
      aiming.appResignedActive()
    }
    let onboarding = Onboarding(defaults: defaults)
    if summoned {
      onboarding.recordSummonFromFinder()
    }
    return OnboardingView(
      library: PackLibrary(
        userPacksDirectory: root.appending(path: "packs"),
        cacheDirectory: root.appending(path: "cache"),
        defaults: defaults
      ),
      onboarding: onboarding,
      iconAiming: aiming,
      playDemo: {}
    )
  }

  /// The height SwiftUI lays the step out in at the width the window gives it.
  func height(of step: some View) -> CGFloat {
    NSHostingView(rootView: step.frame(width: OnboardingView.stepWidth)).fittingSize.height
  }

  /// Every state a step can be in, since the window has to hold whichever is tallest.
  var everyStep: [(String, CGFloat)] {
    [
      ("what it does", height(of: introduction().whatItDoes)),
      ("find it in Finder, not used yet", height(of: introduction().findItInFinder)),
      ("find it in Finder, used", height(of: introduction(summoned: true).findItInFinder)),
      ("aiming, never asked for", height(of: introduction().aimAtIcons)),
      ("aiming, granted", height(of: introduction(trusted: true, wish: true).aimAtIcons)),
      ("aiming, permission missing", height(of: introduction(wish: true).aimAtIcons)),
      ("aiming, requesting", height(of: introduction(requesting: true).aimAtIcons)),
      ("aiming, waiting", height(of: introduction(waiting: true).aimAtIcons)),
    ]
  }

  @Test("no step outgrows the height the window opens at")
  func everyStepFits() {
    for (name, height) in everyStep {
      #expect(
        height <= OnboardingView.stepHeight,
        "\(name) needs \(height)pt of the \(OnboardingView.stepHeight)pt the window reserves"
      )
    }
  }

  @Test("the reserved height is the tallest step's, so no step is given space it cannot justify")
  func reservedHeightIsTheTallestStep() throws {
    let tallest = try #require(everyStep.max { $0.1 < $1.1 })
    #expect(
      tallest.1 == OnboardingView.stepHeight,
      "the tallest step is \(tallest.0) at \(tallest.1)pt, not \(OnboardingView.stepHeight)pt"
    )
  }

  @Test("the permission block is what makes the third step the tallest")
  func thePermissionBlockIsTheTallestState() {
    let missing = height(of: introduction(wish: true).aimAtIcons)
    let granted = height(of: introduction(trusted: true, wish: true).aimAtIcons)
    #expect(missing > granted, "the warning and its button are the extra height to reserve")
  }
  @Test("waiting adds visible status on both permission surfaces", arguments: [false, true])
  func waitingIsRendered(settings: Bool) {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let defaults = UserDefaults(suiteName: "OnboardingLayoutTests-\(UUID().uuidString)")!
    let calls = IconAimingTests.SystemCalls()
    let aiming = IconAiming(
      defaults: defaults,
      prompt: { false },
      trusted: { false },
      openURL: { _ in },
      isAppActive: { true },
      promptOwnsFocus: { calls.promptOwnsFocus }
    )
    let library = PackLibrary(
      userPacksDirectory: root.appending(path: "packs"),
      cacheDirectory: root.appending(path: "cache"),
      defaults: defaults
    )
    let introduction = OnboardingView(
      library: library,
      onboarding: Onboarding(defaults: defaults),
      iconAiming: aiming,
      playDemo: {}
    )
    func contentHeight() -> CGFloat {
      if settings {
        return NSHostingView(
          rootView: SettingsView(library: library, iconAiming: aiming, sound: ShowSound(defaults: defaults))
        ).fittingSize.height
      }
      return height(of: introduction.aimAtIcons)
    }
    let neverAsked = contentHeight()
    aiming.setEnabled(true)
    let requesting = contentHeight()
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    let waiting = contentHeight()
    #expect(requesting > neverAsked, "the initial press renders status before any negative outcome")
    #expect(waiting > neverAsked, "an observed dialog renders status instead of merely hiding the warning")
    aiming.setEnabled(false)
    #expect(contentHeight() == neverAsked, "withdrawing removes the status")
  }

}
