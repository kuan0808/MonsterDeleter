import Foundation
import Observation

/// How far a new user has got, so the app can guide rather than instruct: whether the introduction
/// has been seen, whether the Finder Services item has ever been used, and whether a show has run
/// whose explosions all fell back to the ring because the icons could not be read.
///
/// These are facts about this install, not preferences: nothing here belongs in the Settings
/// window. The introduction can be asked for again from the app window.
@MainActor
@Observable
public final class Onboarding {
  public static let completedKey = "onboardingCompleted"
  public static let summonedFromFinderKey = "hasSummonedFromFinder"
  public static let sawUnaimedFanKey = "sawUnaimedFan"

  /// The introduction has been finished or skipped. Until then the app window opens on it.
  public private(set) var isCompleted: Bool
  /// A show has been summoned from Finder's Services menu at least once: the step that teaches it
  /// says so, instead of leaving the user guessing whether they found the right thing.
  public private(set) var hasSummonedFromFinder: Bool
  /// A show of two or more items ran without a single icon resolved, so every explosion landed in
  /// the ring around the click. The app window offers icon aiming once, quietly, after that.
  public private(set) var sawUnaimedFan: Bool

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    isCompleted = defaults.bool(forKey: Self.completedKey)
    hasSummonedFromFinder = defaults.bool(forKey: Self.summonedFromFinderKey)
    sawUnaimedFan = defaults.bool(forKey: Self.sawUnaimedFanKey)
  }

  public func complete() {
    set(true, forKey: Self.completedKey, to: \.isCompleted)
  }

  /// "Show the introduction again" from the app window.
  public func restart() {
    set(false, forKey: Self.completedKey, to: \.isCompleted)
  }

  public func recordSummonFromFinder() {
    guard !hasSummonedFromFinder else { return }
    set(true, forKey: Self.summonedFromFinderKey, to: \.hasSummonedFromFinder)
  }

  public func recordUnaimedFan() {
    guard !sawUnaimedFan else { return }
    set(true, forKey: Self.sawUnaimedFanKey, to: \.sawUnaimedFan)
  }

  /// Puts the offer of icon aiming away: it stays away until another show's explosions all fall
  /// back to the ring, which is the only thing that raises it again.
  public func dismissAimingTip() {
    set(false, forKey: Self.sawUnaimedFanKey, to: \.sawUnaimedFan)
  }

  private func set(_ value: Bool, forKey key: String, to keyPath: ReferenceWritableKeyPath<Onboarding, Bool>) {
    self[keyPath: keyPath] = value
    defaults.set(value, forKey: key)
  }
}
