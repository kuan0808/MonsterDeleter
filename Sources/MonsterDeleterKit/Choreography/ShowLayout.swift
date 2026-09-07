import Foundation

/// Where everything goes for one show. Points are layer centres in AppKit global coordinates.
public struct ShowLayout: Sendable, Hashable {
  public var entrySide: EntrySide
  public var characterSize: CGSize
  /// Off-screen centre where the walk starts.
  public var start: CGPoint
  /// Centre where the monster stands beside the target.
  public var stand: CGPoint
  /// Off-screen centre where the flight ends.
  public var exit: CGPoint
  /// One explosion centre per item of the selection, capped at `ExplosionFan.maxHits`: a target
  /// whose icon rect resolved sits on that icon's centre, and the rest are fanned around the fan
  /// centre - one on the point, two to six ringing it with no centre hit, and from seven on the
  /// point is hit and the rest fill rings around it.
  public var explosionCenters: [CGPoint]
  public var explosionSize: CGSize
  public var screen: CGRect
  public var margin: CGFloat

  /// The standing monster's frame.
  public var characterFrame: CGRect {
    CGRect(
      x: stand.x - characterSize.width / 2,
      y: stand.y - characterSize.height / 2,
      width: characterSize.width,
      height: characterSize.height
    )
  }

  /// Frame for the ask bubble of a given size: centred over the head, clamped to the screen.
  public func bubbleFrame(size: CGSize) -> CGRect {
    let origin = CGPoint(x: stand.x - size.width / 2, y: characterFrame.maxY + 10)
    return clamped(CGRect(origin: origin, size: size))
  }

  /// Frame for the button row of a given size: centred under the feet, clamped to the screen.
  public func buttonsFrame(size: CGSize) -> CGRect {
    let origin = CGPoint(x: stand.x - size.width / 2, y: characterFrame.minY + 20 - size.height)
    return clamped(CGRect(origin: origin, size: size))
  }

  /// Moves `rect` the shortest distance that keeps it `margin` inside the screen. A rect too big
  /// to fit (a pack text long enough to overflow a small screen) is pinned at the leading margin.
  public func clamped(_ rect: CGRect) -> CGRect {
    let inset = screen.insetBy(dx: margin, dy: margin)
    var result = rect
    result.origin.x = min(max(rect.minX, inset.minX), max(inset.minX, inset.maxX - rect.width))
    result.origin.y = min(max(rect.minY, inset.minY), max(inset.minY, inset.maxY - rect.height))
    return result
  }
}
