import Foundation

/// Every timing and layout constant of the show, in one value.
///
/// The numbers come from the original MonsterDeleter. The pack supplies the
/// tunable part (frame rate, heights, frame indices, walk and fly durations); the geometry
/// offsets are intrinsic to the choreography and not pack-configurable.
///
/// All points are AppKit global coordinates (origin bottom-left, y up). The original's
/// top-left offsets are converted here once: the monster's centre sits `standingDrop` below the
/// target point, and a target with no icon rect of its own explodes `explosionFanRise` above the
/// fan centre (`ExplosionFan`). A target the icon aiming resolved explodes on its icon's centre
/// instead, with no offset of any kind.
public struct Choreography: Sendable, Hashable {
  public var framesPerSecond: Int
  public var frameCount: Int
  public var characterHeight: CGFloat
  public var explosionHeight: CGFloat
  public var pointFrames: ClosedRange<Int>
  public var kickImpactFrame: Int
  public var walkDuration: Duration
  public var walkEasing: Easing
  public var flyDuration: Duration
  public var flyEasing: Easing

  /// Backdrop opacity while aiming with the crosshair.
  public var backdropOpacity: Double
  /// Backdrop fade in when aiming starts.
  public var backdropFadeIn: Duration
  /// Backdrop fade out after the aim click; the `entering` phase.
  public var backdropFadeOut: Duration
  /// Horizontal gap between the monster's near edge and the target.
  public var standingGap: CGFloat
  /// The monster's vertical centre sits this far below the target point.
  public var standingDrop: CGFloat
  /// How far above the fan centre a target with no icon rect of its own explodes.
  ///
  /// This is a *pointer* offset, not sprite geometry. The original had one aim, the right-click,
  /// and lifted every explosion off it by this much (upstream `main.py:497-519` centres
  /// the explosion at `target.y - 40` in top-left coordinates, `config.jsonc` calls it the
  /// explosion y offset). A pointer is not the file: its hotspot is the arrow's tip and it sits
  /// on the icon's label as often as on the icon, so the burst has to rise to cover the file.
  /// An icon rect already *is* the file, so a resolved target takes none of this
  /// (`layout(aim:targetCount:screen:characterAspect:explosionAspect:)`).
  public var explosionFanRise: CGFloat
  /// Ring spacing of the explosion fan when the selection has more than one item.
  public var explosionFanRadius: CGFloat
  /// How far past the screen's right edge the monster flies before the show ends.
  public var exitOvershoot: CGFloat
  /// Minimum distance the ask bubble and buttons keep from the screen edges.
  public var screenMargin: CGFloat

  public init(pack: PackDescriptor) {
    framesPerSecond = pack.framesPerSecond
    frameCount = pack.sheets[.kick]?.frameCount ?? SheetDescriptor.standardFrameCount
    characterHeight = CGFloat(pack.characterHeight)
    explosionHeight = CGFloat(pack.explosionHeight)
    explosionFanRadius = CGFloat(pack.explosionFanRadius)
    pointFrames = pack.pointFrames
    kickImpactFrame = pack.kickImpactFrame
    walkDuration = .seconds(pack.walkSeconds)
    walkEasing = .outQuad
    flyDuration = .seconds(pack.flySeconds)
    flyEasing = .inQuad
    backdropOpacity = 0.35
    backdropFadeIn = .milliseconds(800)
    backdropFadeOut = .milliseconds(500)
    standingGap = 30
    standingDrop = 50
    explosionFanRise = 40
    exitOvershoot = 200
    screenMargin = 12
  }

  /// The choreography of the built-in placeholder pack: the original's numbers.
  public static let standard = Choreography(pack: .placeholder)

  // MARK: Derived timing

  /// Time each sprite frame is shown: 125 ms at 8 fps.
  public var frameDuration: Duration { .seconds(1) / framesPerSecond }

  /// One full sheet played once: 1.875 s for 15 frames at 8 fps (kick, explosion, rescuer).
  public var sheetDuration: Duration { frameDuration * frameCount }

  /// The point gesture: frames 11...14 once, 500 ms.
  public var pointDuration: Duration { frameDuration * pointFrames.count }

  /// Time from the kick's first frame to the impact frame: 625 ms.
  public var impactDelay: Duration { frameDuration * kickImpactFrame }

  /// The point frame a standing monster holds: the last frame of this pack's point range, or the
  /// sheet's last frame when the range reaches past it. `nil` for a sheet without frames.
  public func heldPointFrame(frameCount: Int) -> Int? {
    guard frameCount > 0 else { return nil }
    return min(max(pointFrames.upperBound, 0), frameCount - 1)
  }

  /// The explosion plays for a full sheet from the impact frame.
  public var explosionDuration: Duration { sheetDuration }

  /// How long a timed phase lasts, or `nil` for phases that wait for the user or are terminal.
  public func duration(of phase: ShowPhase) -> Duration? {
    switch phase {
    case .entering: return backdropFadeOut
    case .walking: return walkDuration
    case .kicking: return impactDelay
    case .exploding: return sheetDuration - impactDelay
    case .rescuing: return sheetDuration
    case .flying: return flyDuration
    case .aiming, .asking, .done, .cancelled: return nil
    }
  }

  // MARK: Layout

  /// Positions for one show, given the show's aim, the number of items in the selection, the
  /// screen it is on and the sprite aspect ratios (width / height) of the character and
  /// explosion frames.
  ///
  /// The aim's icons place their own explosions - each on its icon's centre - and hold the
  /// monster clear of the icon's edge rather than of a bare point; whatever the accessibility
  /// tier could not resolve is fanned `explosionFanRise` above the aim's fan centre, as it always
  /// was. The monster itself is always on screen, in both axes, however wide the selection's
  /// icons spread. A fan of two or more is kept inside the screen; an icon's explosion never is,
  /// nor is a lone one - both sit on their own point and the panel clips them.
  public func layout(
    aim: TargetAim,
    targetCount: Int,
    screen: CGRect,
    characterAspect: CGFloat,
    explosionAspect: CGFloat
  ) -> ShowLayout {
    let target = aim.point
    let size = CGSize(width: characterHeight * characterAspect, height: characterHeight)
    let halfWidth = size.width / 2
    // A resolved icon is a shape, not a point: the gap is measured from the icon's own edge on
    // the side the monster comes from, so a wide selection is not straddled from its middle.
    let leftStandX = (aim.iconRects.map(\.minX).min() ?? target.x) - standingGap - halfWidth
    let rightStandX = (aim.iconRects.map(\.maxX).max() ?? target.x) + standingGap + halfWidth
    // The left is the entry side whenever the monster fits there, and the right only when it
    // fits there in turn: a selection whose icons span more than the screen has no side that
    // clears them, and the clamp below keeps it visible rather than sending it off the far edge.
    let fitsLeft = leftStandX - halfWidth >= screen.minX
    let fitsRight = rightStandX + halfWidth <= screen.maxX
    let side: EntrySide = fitsLeft || !fitsRight ? .left : .right
    let standX = min(
      max(side == .left ? leftStandX : rightStandX, screen.minX + halfWidth),
      screen.maxX - halfWidth
    )
    let standY = min(max(target.y - standingDrop, screen.minY + size.height / 2), screen.maxY - size.height / 2)
    let startX = side == .left ? screen.minX - halfWidth : screen.maxX + halfWidth
    let explosionSize = CGSize(width: explosionHeight * explosionAspect, height: explosionHeight)
    var layout = ShowLayout(
      entrySide: side,
      characterSize: size,
      start: CGPoint(x: startX, y: standY),
      stand: CGPoint(x: standX, y: standY),
      exit: CGPoint(x: screen.maxX + exitOvershoot + halfWidth, y: standY),
      explosionCenters: [],
      explosionSize: explosionSize,
      screen: screen,
      margin: screenMargin
    )
    // A resolved target explodes on its icon's centre and nowhere else. Nothing is owed to sprite
    // geometry either: every built-in pack draws its burst centred in the frame cell, so the
    // layer's centre is the burst's own centre (`ShippedPackTests`
    // measures the alpha centroid of all 15 frames of all three packs; the largest departure from
    // the cell centre is 6.6 pt at the pack's own explosion height, against a Finder icon of
    // about 64 pt). `explosionFanRise` stays with the fan, whose centre is a pointer.
    let onIcons = aim.iconRects.prefix(ExplosionFan.maxHits).map { CGPoint(x: $0.midX, y: $0.midY) }
    let unresolved = max(min(targetCount - aim.iconRects.count, ExplosionFan.maxHits - onIcons.count), 0)
    let fan = ExplosionFan.centers(
      around: CGPoint(x: aim.fanCenter.x, y: aim.fanCenter.y + explosionFanRise),
      count: unresolved,
      radius: explosionFanRadius
    )
    // Only the fan is clamped, and only when the show has more than one target: a ring around a
    // pointer reads better piled up at the edge than half off screen, while an icon's burst has
    // somewhere it must be, so it stays on its icon and the panel clips whatever runs past the
    // edge - the same bargain a single explosion has always had.
    layout.explosionCenters =
      onIcons
      + (targetCount == 1
        ? fan
        : fan.map { center in
          let frame = CGRect(
            x: center.x - explosionSize.width / 2,
            y: center.y - explosionSize.height / 2,
            width: explosionSize.width,
            height: explosionSize.height
          )
          let clamped = layout.clamped(frame)
          return CGPoint(x: clamped.midX, y: clamped.midY)
        })
    return layout
  }
}
