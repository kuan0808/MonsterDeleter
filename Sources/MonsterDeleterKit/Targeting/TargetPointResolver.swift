import Foundation

/// Decides whether a recorded click can stand in for the file's position.
///
/// Spike decision 2: never read `NSEvent.mouseLocation` in the service handler (it points at the
/// menu item), and when there is no usable sample fall back to the crosshair, never to the mouse.
public enum TargetPointResolver {
  /// A right-click older than this predates the Services menu that invoked us.
  public static let maxSampleAge: Duration = .seconds(15)

  /// The target point, or `nil` when the show must start with the aiming phase.
  public static func resolve(
    _ sample: TargetSample?,
    now: ContinuousClock.Instant,
    maxAge: Duration = maxSampleAge
  ) -> CGPoint? {
    guard let sample, sample.takenAt <= now else { return nil }
    guard sample.takenAt.duration(to: now) <= maxAge else { return nil }
    return sample.point
  }
}
