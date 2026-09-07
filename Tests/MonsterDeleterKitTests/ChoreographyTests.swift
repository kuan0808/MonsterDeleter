import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("Choreography timing table")
struct ChoreographyTimingTests {
  let choreography = Choreography.standard

  @Test("frame rate and sheet timing match the original")
  func frameTiming() {
    #expect(choreography.framesPerSecond == 8)
    #expect(choreography.frameCount == 15)
    #expect(choreography.frameDuration == .milliseconds(125))
    #expect(choreography.sheetDuration == .milliseconds(1875))
    #expect(choreography.pointFrames == 11...14)
    #expect(choreography.pointDuration == .milliseconds(500))
    #expect(choreography.kickImpactFrame == 5)
    #expect(choreography.impactDelay == .milliseconds(625))
    #expect(choreography.explosionDuration == .milliseconds(1875))
  }

  @Test("the held point frame is the pack's own last point frame, clamped to its sheet")
  func heldPointFrame() {
    #expect(choreography.heldPointFrame(frameCount: 15) == 14)
    var wide = choreography
    wide.pointFrames = 16...19
    #expect(wide.heldPointFrame(frameCount: 20) == 19)
    #expect(wide.heldPointFrame(frameCount: 15) == 14, "a shorter sheet holds its last frame")
    #expect(wide.heldPointFrame(frameCount: 0) == nil)
  }

  @Test("walk, flight and backdrop constants match the original")
  func motionConstants() {
    #expect(choreography.walkDuration == .milliseconds(4500))
    #expect(choreography.walkEasing == .outQuad)
    #expect(choreography.flyDuration == .milliseconds(2000))
    #expect(choreography.flyEasing == .inQuad)
    #expect(choreography.characterHeight == 250)
    #expect(choreography.explosionHeight == 150)
    #expect(choreography.backdropOpacity == 0.35)
    #expect(choreography.backdropFadeIn == .milliseconds(800))
    #expect(choreography.backdropFadeOut == .milliseconds(500))
    #expect(choreography.standingGap == 30)
    #expect(choreography.standingDrop == 50)
    #expect(choreography.explosionFanRise == 40)
    #expect(choreography.explosionFanRadius == 75)
    #expect(choreography.exitOvershoot == 200)
  }

  @Test(
    "phase durations",
    arguments: [
      (ShowPhase.entering, Duration.milliseconds(500)),
      (.walking, .milliseconds(4500)),
      (.kicking, .milliseconds(625)),
      (.exploding, .milliseconds(1250)),
      (.rescuing, .milliseconds(1875)),
      (.flying, .milliseconds(2000)),
    ]
  )
  func timedPhase(phase: ShowPhase, expected: Duration) {
    #expect(choreography.duration(of: phase) == expected)
  }

  @Test(
    "phases that wait for the user or end the show have no duration",
    arguments: [ShowPhase.aiming, .asking, .done, .cancelled]
  )
  func untimedPhase(phase: ShowPhase) {
    #expect(choreography.duration(of: phase) == nil)
  }

  @Test("the timed phases after the kick add up to the original's 5.75 s")
  func afterKickTotal() {
    let phases: [ShowPhase] = [.kicking, .exploding, .rescuing, .flying]
    let total = phases.compactMap(choreography.duration(of:)).reduce(Duration.zero, +)
    #expect(total == .milliseconds(5750))
  }
}

@Suite("Choreography layout")
struct ChoreographyLayoutTests {
  let choreography = Choreography.standard
  let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
  let characterAspect: CGFloat = 0.5625
  let explosionAspect: CGFloat = 0.75

  func layout(target: CGPoint, count: Int = 1, screen: CGRect? = nil) -> ShowLayout {
    layout(aim: TargetAim(point: target), count: count, screen: screen)
  }

  func layout(aim: TargetAim, count: Int = 1, screen: CGRect? = nil) -> ShowLayout {
    choreography.layout(
      aim: aim,
      targetCount: count,
      screen: screen ?? self.screen,
      characterAspect: characterAspect,
      explosionAspect: explosionAspect
    )
  }

  @Test("the monster enters from the left and stands beside the target, 50 pt lower")
  func standsBesideTarget() {
    let layout = layout(target: CGPoint(x: 1000, y: 500))
    #expect(layout.entrySide == .left)
    #expect(layout.characterSize == CGSize(width: 140.625, height: 250))
    #expect(layout.stand == CGPoint(x: 899.6875, y: 450))
    #expect(layout.start == CGPoint(x: -70.3125, y: 450))
    #expect(layout.exit == CGPoint(x: 3710.3125, y: 450))
    #expect(layout.characterFrame.maxX == 970)
  }

  @Test("the explosion sits on the target, 40 pt higher, at height 150")
  func explosionPlacement() {
    let layout = layout(target: CGPoint(x: 1000, y: 500))
    #expect(layout.explosionCenters == [CGPoint(x: 1000, y: 540)])
    #expect(layout.explosionSize == CGSize(width: 112.5, height: 150))
  }

  @Test("a selection fans one explosion per item around the risen point, 75 pt out")
  func explosionFan() {
    let layout = layout(target: CGPoint(x: 1000, y: 500), count: 7)
    #expect(layout.explosionCenters.count == 7)
    #expect(layout.explosionCenters[0] == CGPoint(x: 1000, y: 540))
    #expect(layout.explosionCenters[1] == CGPoint(x: 1075, y: 540))
    #expect(layout.explosionCenters[4] == CGPoint(x: 925, y: 540))
  }

  @Test("a fan in the middle of the screen is not moved")
  func explosionFanUnmoved() {
    let centers = layout(target: CGPoint(x: 1720, y: 720), count: 12).explosionCenters
    #expect(centers[0] == CGPoint(x: 1720, y: 760))
    let farthest = centers.map { hypot($0.x - 1720, $0.y - 760) }.max() ?? 0
    #expect(abs(farthest - 150) <= 1, "the second ring sits two radii out, to the nearest point")
  }

  @Test(
    "a lone explosion keeps its point at the screen edge, unclamped",
    arguments: [CGPoint(x: 1000, y: 1420), CGPoint(x: 5, y: 10), CGPoint(x: 3438, y: 1439)]
  )
  func singleExplosionUnclamped(target: CGPoint) {
    #expect(layout(target: target).explosionCenters == [CGPoint(x: target.x, y: target.y + 40)])
  }

  @Test("a selection larger than the fan cap draws at most nineteen explosions")
  func explosionFanCap() {
    #expect(layout(target: CGPoint(x: 1720, y: 720), count: 2000).explosionCenters.count == 19)
  }

  @Test(
    "every explosion of a fan stays inside the screen, whichever corner the target is in",
    arguments: [CGPoint(x: 0, y: 0), CGPoint(x: 3440, y: 0), CGPoint(x: 0, y: 1440), CGPoint(x: 3440, y: 1440)],
    [2, 5, 12]
  )
  func explosionFanBounds(target: CGPoint, count: Int) {
    let layout = layout(target: target, count: count)
    let inset = screen.insetBy(dx: layout.margin, dy: layout.margin)
    #expect(layout.explosionCenters.count == count)
    for center in layout.explosionCenters {
      let frame = CGRect(
        x: center.x - layout.explosionSize.width / 2,
        y: center.y - layout.explosionSize.height / 2,
        width: layout.explosionSize.width,
        height: layout.explosionSize.height
      )
      #expect(inset.contains(frame), "\(frame) leaves \(inset)")
    }
  }

  @Test("a target near the left edge makes the monster enter from the right, mirrored")
  func entersFromRightNearLeftEdge() {
    let layout = layout(target: CGPoint(x: 100, y: 500))
    #expect(layout.entrySide == .right)
    #expect(layout.entrySide.isMirrored)
    #expect(layout.stand == CGPoint(x: 200.3125, y: 450))
    #expect(layout.start == CGPoint(x: 3510.3125, y: 450))
    #expect(layout.exit.x > layout.screen.maxX)
  }

  @Test("the side switches exactly when the standing monster would leave the screen")
  func entrySideThreshold() {
    // Stand left edge = target.x - 30 - 140.625; it fits while that is >= 0.
    #expect(layout(target: CGPoint(x: 170.625, y: 500)).entrySide == .left)
    #expect(layout(target: CGPoint(x: 170.624, y: 500)).entrySide == .right)
  }

  @Test("a secondary screen's origin is honoured")
  func secondaryScreen() {
    let screen = CGRect(x: 1239, y: -982, width: 1512, height: 982)
    let layout = layout(target: CGPoint(x: 1300, y: -500), screen: screen)
    #expect(layout.entrySide == .right)
    #expect(layout.start.x == screen.maxX + 70.3125)
    #expect(layout.exit.x == screen.maxX + 200 + 70.3125)
  }

  @Test("the monster stays on screen vertically")
  func verticalClamp() {
    #expect(layout(target: CGPoint(x: 1000, y: 20)).stand.y == 125)
    #expect(layout(target: CGPoint(x: 1000, y: 1439)).stand.y == 1315)
  }

  @Test("the bubble is centred over the head and the buttons under the feet")
  func askPlacement() {
    let layout = layout(target: CGPoint(x: 1000, y: 500))
    let bubble = layout.bubbleFrame(size: CGSize(width: 200, height: 60))
    #expect(bubble.midX == layout.stand.x)
    #expect(bubble.minY == layout.characterFrame.maxY + 10)
    let buttons = layout.buttonsFrame(size: CGSize(width: 260, height: 40))
    #expect(buttons.midX == layout.stand.x)
    #expect(buttons.maxY == layout.characterFrame.minY + 20)
  }

  @Test("the bubble and buttons are clamped inside the screen with the margin")
  func askClamping() {
    let top = layout(target: CGPoint(x: 3400, y: 1430))
    let bubble = top.bubbleFrame(size: CGSize(width: 300, height: 60))
    #expect(bubble.maxY == 1428)
    #expect(bubble.maxX == 3428)
    let bottom = layout(target: CGPoint(x: 1000, y: 5))
    let buttons = bottom.buttonsFrame(size: CGSize(width: 260, height: 40))
    #expect(buttons.minY == 12)
  }

  @Test("a bubble wider or taller than the inset screen is pinned at the leading margin")
  func oversizedRectPinnedAtMargin() {
    let small = CGRect(x: 0, y: 0, width: 400, height: 300)
    let layout = layout(target: CGPoint(x: 200, y: 150), screen: small)
    let oversized = layout.bubbleFrame(size: CGSize(width: 900, height: 700))
    #expect(oversized.minX == small.minX + layout.margin)
    #expect(oversized.minY == small.minY + layout.margin)
  }

  @Test("every selection size from one to two thousand lays out finite, bounded and capped")
  func anySelectionSizeIsBounded() {
    let targets = [CGPoint(x: 1720, y: 720), CGPoint(x: 0, y: 0), CGPoint(x: 3440, y: 1440), CGPoint(x: 12, y: 1400)]
    let inset = screen.insetBy(dx: choreography.screenMargin, dy: choreography.screenMargin)
    for count in 1...2000 {
      for target in targets {
        let layout = layout(target: target, count: count)
        #expect(layout.explosionCenters.count == min(count, ExplosionFan.maxHits))
        for point in [layout.start, layout.stand, layout.exit] + layout.explosionCenters {
          #expect(point.x.isFinite && point.y.isFinite, "\(point) for \(count) items at \(target)")
        }
        #expect(screen.insetBy(dx: -layout.characterSize.width, dy: 0).contains(layout.stand))
        #expect(layout.exit.x > screen.maxX)
        #expect(layout.start.x < screen.minX || layout.start.x > screen.maxX)
        if count > 1 {
          for center in layout.explosionCenters {
            let frame = CGRect(
              x: center.x - layout.explosionSize.width / 2,
              y: center.y - layout.explosionSize.height / 2,
              width: layout.explosionSize.width,
              height: layout.explosionSize.height
            )
            #expect(inset.contains(frame), "\(frame) leaves the screen for \(count) items at \(target)")
          }
        }
      }
    }
  }

  @Test("a swap re-lays out for the new pack's sprite width and leaves the target-side geometry alone")
  func swapKeepsTheSpot() {
    let target = CGPoint(x: 1000, y: 500)
    let before = layout(target: target, count: 7)
    let after = choreography.layout(
      aim: TargetAim(point: target),
      targetCount: 7,
      screen: screen,
      characterAspect: 0.8,
      explosionAspect: 1
    )
    #expect(after.entrySide == before.entrySide)
    #expect(after.stand.y == before.stand.y)
    #expect(after.characterFrame.maxX == before.characterFrame.maxX, "the near edge keeps the standing gap")
    #expect(after.characterSize.width == 200)
    #expect(after.explosionCenters == before.explosionCenters)
    #expect(after.explosionSize == CGSize(width: 150, height: 150))
  }
}

/// What the accessibility tier adds to the layout: the icons it resolved place their own
/// explosions and push the monster clear of the icon rather than of a bare point.
@Suite("Choreography layout with icons")
struct ChoreographyIconLayoutTests {
  let choreography = Choreography.standard
  let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
  let click = CGPoint(x: 1584, y: 211)

  /// A 64 pt desktop icon centred on (1000, 800), and its neighbour 112 pt to the right.
  let firstIcon = CGRect(x: 968, y: 768, width: 64, height: 64)
  let secondIcon = CGRect(x: 1080, y: 768, width: 64, height: 64)

  func layout(aim: TargetAim, count: Int) -> ShowLayout {
    choreography.layout(
      aim: aim,
      targetCount: count,
      screen: screen,
      characterAspect: 0.5625,
      explosionAspect: 0.75
    )
  }

  func aim(_ rects: [CGRect], fanCenter: CGPoint? = nil) -> TargetAim {
    let bounds = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
    return TargetAim(
      point: CGPoint(x: bounds.midX, y: bounds.midY),
      iconRects: rects,
      fanCenter: fanCenter
    )
  }

  @Test("the explosion sits on the icon's centre, with no rise")
  func explosionOnTheIcon() {
    #expect(layout(aim: aim([firstIcon]), count: 1).explosionCenters == [CGPoint(x: 1000, y: 800)])
  }

  /// The layout contract: every burst of a multiple selection is centred on its own icon, whatever
  /// size and wherever the icons sit. The pointer offset belongs to the fan, never to an icon.
  @Test(
    "every resolved target explodes on the centre of its own icon rect",
    arguments: [
      [CGRect(x: 0, y: 0, width: 16, height: 16)],
      [CGRect(x: 968, y: 768, width: 64, height: 64), CGRect(x: 1080, y: 768, width: 64, height: 64)],
      [
        CGRect(x: 121, y: 1301, width: 128, height: 128),
        CGRect(x: 900, y: 33, width: 32, height: 32),
        CGRect(x: 2400, y: 700, width: 64, height: 48),
      ],
    ]
  )
  func explosionOnEveryIconCentre(icons: [CGRect]) {
    let centers = layout(aim: aim(icons, fanCenter: click), count: icons.count).explosionCenters
    #expect(centers == icons.map { CGPoint(x: $0.midX, y: $0.midY) })
  }

  @Test("an icon against the screen edge keeps its explosion on the icon, clipped rather than moved")
  func iconExplosionUnclamped() {
    let atTheTop = CGRect(x: 968, y: 1400, width: 64, height: 64)
    let centers = layout(aim: aim([firstIcon, atTheTop]), count: 2).explosionCenters
    #expect(centers == [CGPoint(x: 1000, y: 800), CGPoint(x: 1000, y: 1432)])
  }

  @Test("the monster stands clear of the icon, not of its centre")
  func standsClearOfTheIcon() {
    let withIcon = layout(aim: aim([firstIcon]), count: 1)
    #expect(withIcon.entrySide == .left)
    // 30 pt of gap past the icon's left edge, where a bare point leaves 30 pt past the point.
    #expect(withIcon.characterFrame.maxX == 938)
    #expect(withIcon.stand == CGPoint(x: 867.6875, y: 750))
  }

  @Test("the monster keeps its clearance when it has to come from the right")
  func standsClearFromTheRight() {
    let atTheLeftEdge = CGRect(x: 10, y: 768, width: 64, height: 64)
    let layout = layout(aim: aim([atTheLeftEdge]), count: 1)
    #expect(layout.entrySide == .right)
    // 30 pt of gap past the icon's right edge, which is at 74.
    #expect(layout.characterFrame.minX == 104)
  }

  @Test("the targets that resolved explode on their icons and the rest fan around the right-click")
  func iconsAndFanTogether() {
    let centers = layout(aim: aim([firstIcon, secondIcon], fanCenter: click), count: 3).explosionCenters
    #expect(centers == [CGPoint(x: 1000, y: 800), CGPoint(x: 1112, y: 800), CGPoint(x: 1584, y: 251)])
  }

  @Test("the drawn hits still stop at nineteen when icons and a fan share the show")
  func capAcrossIconsAndFan() {
    let centers = layout(aim: aim([firstIcon, secondIcon], fanCenter: click), count: 2000).explosionCenters
    #expect(centers.count == ExplosionFan.maxHits)
    #expect(centers.prefix(2) == [CGPoint(x: 1000, y: 800), CGPoint(x: 1112, y: 800)])
  }

  @Test("a selection whose icons all resolved has no fan left to draw")
  func noFanLeft() {
    #expect(layout(aim: aim([firstIcon, secondIcon]), count: 2).explosionCenters.count == 2)
  }

  /// Select-all in a full-window icon view: the icons span more of the screen than the monster
  /// can stand clear of on either side, so the clearance alone would walk it off an edge.
  func wideSelection(from minX: CGFloat, to maxX: CGFloat, y: CGFloat) -> TargetAim {
    let icons = stride(from: minX, through: maxX - 64, by: 112).map {
      CGRect(x: $0, y: y, width: 64, height: 64)
    }
    return aim(icons)
  }

  @Test("a selection wider than the screen still leaves the monster on screen")
  func wideSelectionStaysOnScreen() {
    let layout = layout(aim: wideSelection(from: 40, to: 3400, y: 700), count: 30)
    #expect(screen.contains(layout.characterFrame), "\(layout.characterFrame) leaves \(screen)")
  }

  @Test("a selection wider than a screen with a negative origin stays on that screen")
  func wideSelectionOnASecondaryScreen() {
    let screen = CGRect(x: 1239, y: -982, width: 1512, height: 982)
    let aim = wideSelection(from: 1289, to: 2701, y: -400)
    let layout = choreography.layout(
      aim: aim,
      targetCount: aim.iconRects.count,
      screen: screen,
      characterAspect: 0.5625,
      explosionAspect: 0.75
    )
    #expect(screen.contains(layout.characterFrame), "\(layout.characterFrame) leaves \(screen)")
  }
}
