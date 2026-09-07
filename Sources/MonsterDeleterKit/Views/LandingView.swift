import SwiftUI

/// The app's one window. It opens on the introduction until that has been finished or skipped, and
/// on the home screen after that; the menu bar item opens it again, and the guide is a sheet over
/// it. Preferences are not here - they are in the Settings window, where macOS keeps them.
public struct LandingView: View {
  public static let windowID = "landing"

  /// The height the window opens at and keeps, whichever scene is in it. It is the height of the
  /// TALLEST state the window can reach: the home screen with the aiming offer up, which appears
  /// after a show of two or more items whose icons could not be read (`Onboarding.sawUnaimedFan`).
  /// The introduction is the next tallest and the plain home screen the shortest.
  ///
  /// One height for all of them, because the window is sized from its content
  /// (`.windowResizability(.contentSize)`) and does not grow when that content changes underneath
  /// it - and both of the taller states appear in a window already open on the shortest one:
  /// **Show the introduction again**, and a show that ends in a ring. Without the reservation each
  /// of those would be drawn straight through the buttons at the foot of the window.
  ///
  /// A new state, or a copy change to one of these, has to be measured again:
  /// `LandingLayoutTests` fails when a state outgrows this number.
  public static let contentHeight: CGFloat = 403

  private let library: PackLibrary
  private let onboarding: Onboarding
  private let iconAiming: IconAiming
  private let playDemo: () -> Void

  public init(
    library: PackLibrary,
    onboarding: Onboarding,
    iconAiming: IconAiming,
    playDemo: @escaping () -> Void
  ) {
    self.library = library
    self.onboarding = onboarding
    self.iconAiming = iconAiming
    self.playDemo = playDemo
  }

  public var body: some View {
    Group {
      if onboarding.isCompleted {
        HomeView(onboarding: onboarding, iconAiming: iconAiming, playDemo: playDemo)
      } else {
        OnboardingView(
          library: library,
          onboarding: onboarding,
          iconAiming: iconAiming,
          playDemo: playDemo
        )
      }
    }
    .frame(height: Self.contentHeight)
  }
}
