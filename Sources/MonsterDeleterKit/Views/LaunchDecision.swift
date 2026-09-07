/// What kind of launch this is, decided from the environment before any scene is built.
///
/// A launch carrying `MONSTER_AUTOPLAY` or `MONSTER_EXPORT_PLACEHOLDER` is headless: it plays one
/// judged show or writes a pack out and quits, so it shows no window and wears no character - the
/// self-test forces the placeholder itself, and loading a character it will never wear would only
/// spend the run's time and write to the same slicing cache the run may be reading.
///
/// Otherwise the app window opens by itself until the introduction has been finished or skipped, so
/// someone who quit halfway through meets it again; after that the menu bar item opens it.
public struct LaunchDecision: Sendable, Equatable {
  private static let headlessVariables = ["MONSTER_AUTOPLAY", "MONSTER_EXPORT_PLACEHOLDER"]

  /// A self-test or an export run rather than someone using the app.
  public let isHeadless: Bool
  /// Whether the app window is presented at launch.
  public let opensLandingWindow: Bool

  public init(environment: [String: String], hasCompletedOnboarding: Bool) {
    isHeadless = Self.headlessVariables.contains { !(environment[$0] ?? "").isEmpty }
    opensLandingWindow = !isHeadless && !hasCompletedOnboarding
  }
}
