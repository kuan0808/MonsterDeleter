import Foundation

/// The two easing curves the original show uses for its position tweens.
///
/// `value(at:)` is the exact quadratic curve. `controlPoints` is the cubic Bézier
/// approximation Core Animation can play (`CAMediaTimingFunction(controlPoints:)`).
public enum Easing: Sendable, Hashable {
  /// Qt `OutQuad`: fast start, decelerating. Used for the walk in.
  case outQuad
  /// Qt `InQuad`: slow start, accelerating. Used for the flight out.
  case inQuad

  /// Progress in `0...1` for a normalised time `t` in `0...1`.
  public func value(at t: Double) -> Double {
    let clamped = min(max(t, 0), 1)
    switch self {
    case .outQuad: return 1 - (1 - clamped) * (1 - clamped)
    case .inQuad: return clamped * clamped
    }
  }

  /// Cubic Bézier control points (x1, y1, x2, y2) approximating the curve.
  public var controlPoints: (x1: Float, y1: Float, x2: Float, y2: Float) {
    switch self {
    case .outQuad: return (0.25, 0.46, 0.45, 0.94)
    case .inQuad: return (0.55, 0.085, 0.68, 0.53)
    }
  }
}
