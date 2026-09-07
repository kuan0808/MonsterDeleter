import Foundation

/// Where the explosions of a selection go: one hit per item, fanned around the target point so
/// they read as many hits rather than one. Two to six hits sit on a ring around the point,
/// spread evenly from the right, counterclockwise. From seven on, the point itself gets a hit
/// and the rest fill rings of six, twelve, ... at one, two, ... radii. Offsets are whole points
/// so the sprites stay crisp.
///
/// The drawn hits stop at `maxHits`, the centre plus two full rings: a larger selection still
/// trashes every item and the ask bubble still names the true count, but the fan reads the same
/// and the stage never draws more than that many overlapping sprites.
public enum ExplosionFan {
  /// The most hits the fan ever draws: 1 centre + 6 + 12.
  public static let maxHits = 19

  public static func centers(around center: CGPoint, count: Int, radius: CGFloat) -> [CGPoint] {
    guard count > 0 else { return [] }
    let hits = min(count, maxHits)
    var centers: [CGPoint] = hits == 1 || hits > 6 ? [center] : []
    var ring = 1
    while centers.count < hits {
      let slots = min(6 * ring, hits - centers.count)
      let distance = radius * CGFloat(ring)
      for slot in 0..<slots {
        let angle = 2 * .pi * CGFloat(slot) / CGFloat(slots)
        centers.append(
          CGPoint(
            x: center.x + wholePoints(distance * cos(angle)),
            y: center.y + wholePoints(distance * sin(angle))
          )
        )
      }
      ring += 1
    }
    return centers
  }

  /// Rounds to whole points after snapping to thousandths, so a half point that floating-point
  /// error lands a hair below (`sin(210°) * 75`) rounds the same way as its mirror image.
  private static func wholePoints(_ value: CGFloat) -> CGFloat {
    ((value * 1000).rounded() / 1000).rounded()
  }
}
