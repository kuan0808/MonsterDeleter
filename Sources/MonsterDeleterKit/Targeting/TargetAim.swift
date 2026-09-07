import Foundation

/// Where one show aims. A show either has an aim or comes up with the crosshair, so the absence
/// of an aim is the optional, never a field of this value.
///
/// The plain aim is one point: the right-click, or the click the user made on the crosshair.
/// The accessibility tier fills the rest in, so the monster can walk to the icons themselves
/// and every target it resolved can explode on its own icon.
public struct TargetAim: Sendable, Hashable {
  /// Where the monster walks to and stands beside, in AppKit global coordinates.
  public var point: CGPoint
  /// Every icon rect the accessibility tier resolved, in the selection's order. An icon is a
  /// shape rather than a point, so the choreography can stand the monster clear of the icon it
  /// walks up to and explode each target on its own icon.
  public var iconRects: [CGRect]
  /// Where the targets that did not resolve are fanned: the right-click when there was one, the
  /// icons' own centre otherwise.
  public var fanCenter: CGPoint

  public init(
    point: CGPoint,
    iconRects: [CGRect] = [],
    fanCenter: CGPoint? = nil
  ) {
    self.point = point
    self.iconRects = iconRects
    self.fanCenter = fanCenter ?? point
  }
}
