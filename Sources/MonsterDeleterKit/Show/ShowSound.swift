import Foundation
import Observation

/// Whether the show is allowed to make a noise. Every pack ships music, a voice line and an
/// explosion, and someone running this in an office needs one switch that silences all three.
/// On by default: the sound is half the joke.
@MainActor
@Observable
public final class ShowSound {
  public static let preferenceKey = "playsShowSound"

  public private(set) var isEnabled: Bool

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    // `object(forKey:)` rather than `bool(forKey:)`: an install that has never touched the switch
    // gets sound, and `bool` would read a missing value as off.
    isEnabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
  }

  public func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    defaults.set(enabled, forKey: Self.preferenceKey)
  }
}
