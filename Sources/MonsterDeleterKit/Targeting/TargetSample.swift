import Foundation

/// The last right-click or control-click seen anywhere on screen, in AppKit global coordinates.
public struct TargetSample: Sendable, Hashable {
  public var point: CGPoint
  public var takenAt: ContinuousClock.Instant

  public init(point: CGPoint, takenAt: ContinuousClock.Instant) {
    self.point = point
    self.takenAt = takenAt
  }
}
