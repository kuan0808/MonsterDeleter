import AppKit
import SwiftUI
import Testing

@testable import MonsterDeleterKit

/// The app's one window is sized from its content and does not grow when that content changes
/// underneath it, and two of its states appear in a window already open on a shorter one: **Show
/// the introduction again**, and the aiming offer that a show ending in a ring raises. So the
/// window reserves one height for all of them, and every state is laid out for real here and
/// measured against it - a state that outgrows it is drawn straight through the buttons at the
/// foot of the window.
@MainActor
@Suite("The window's one height holds every state")
struct LandingLayoutTests {
  init() {
    // Both scenes draw the app icon, and `NSApp` is nil in a test process until something asks.
    _ = NSApplication.shared
  }

  /// The state's own defaults suite and empty pack folder, so nothing leaks between states and
  /// nothing here asks macOS for the Accessibility permission.
  private func parts(sawUnaimedFan: Bool) -> (PackLibrary, Onboarding, IconAiming) {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "LandingLayoutTests-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: "LandingLayoutTests-\(UUID().uuidString)")!
    let onboarding = Onboarding(defaults: defaults)
    if sawUnaimedFan {
      onboarding.recordUnaimedFan()
    }
    let library = PackLibrary(
      userPacksDirectory: root.appending(path: "packs"),
      cacheDirectory: root.appending(path: "cache"),
      defaults: defaults
    )
    let aiming = IconAiming(defaults: defaults, prompt: { false }, trusted: { false }, openURL: { _ in })
    return (library, onboarding, aiming)
  }

  func home(sawUnaimedFan: Bool) -> HomeView {
    let (_, onboarding, aiming) = parts(sawUnaimedFan: sawUnaimedFan)
    return HomeView(onboarding: onboarding, iconAiming: aiming, playDemo: {})
  }

  func introduction() -> OnboardingView {
    let (library, onboarding, aiming) = parts(sawUnaimedFan: false)
    return OnboardingView(library: library, onboarding: onboarding, iconAiming: aiming, playDemo: {})
  }

  /// The height SwiftUI lays the scene out in; both scenes set the window's width themselves.
  func height(of scene: some View) -> CGFloat {
    NSHostingView(rootView: scene).fittingSize.height
  }

  /// Every state the one window can be in, since it has to hold whichever is tallest.
  var everyState: [(String, CGFloat)] {
    [
      ("the introduction", height(of: introduction())),
      ("the home screen", height(of: home(sawUnaimedFan: false))),
      ("the home screen with the aiming offer", height(of: home(sawUnaimedFan: true))),
    ]
  }

  @Test("no state outgrows the height the window reserves")
  func everyStateFits() {
    for (name, height) in everyState {
      #expect(
        height <= LandingView.contentHeight,
        "\(name) needs \(height)pt of the \(LandingView.contentHeight)pt the window reserves"
      )
    }
  }

  /// The two growths the reservation exists for, each one appearing in a window already open on
  /// the home screen: without it both would draw over the controls under them.
  @Test("the aiming offer and the introduction are both taller than the home screen they open over")
  func bothGrowthsAreRealAndReserved() {
    let plain = height(of: home(sawUnaimedFan: false))
    let withTip = height(of: home(sawUnaimedFan: true))
    let introduction = height(of: introduction())
    #expect(withTip > plain, "the aiming offer appears in place and makes the home screen taller")
    #expect(introduction > plain, "asking for the introduction again grows the same window")
    #expect(max(withTip, introduction) <= LandingView.contentHeight)
  }
}
