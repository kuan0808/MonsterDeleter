/// The screen edge the monster walks in from.
///
/// The original always entered from the left, which pushed the monster off-screen for
/// targets near the left edge. The side is now chosen so the walk fits (`ShowLayout`).
public enum EntrySide: Sendable, Hashable {
  case left
  case right

  /// Whether the walk, point and kick sprites must be mirrored horizontally.
  /// Placeholder and upstream sheets face right; entering from the right means facing left.
  public var isMirrored: Bool { self == .right }
}
