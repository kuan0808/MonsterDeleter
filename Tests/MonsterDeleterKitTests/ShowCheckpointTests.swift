import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("ShowCheckpoint")
struct ShowCheckpointTests {
  let choreography = Choreography.standard

  @Test("the six checkpoints follow the show in order and name their files by rank")
  func order() {
    #expect(ShowCheckpoint.allCases.map(\.phase) == [.walking, .asking, .kicking, .exploding, .rescuing, .flying])
    #expect(
      ShowCheckpoint.allCases.map(\.fileName) == [
        "01-walk.png", "02-point.png", "03-kick.png", "04-explosion.png", "05-rescuer.png", "06-fly.png",
      ]
    )
  }

  @Test(
    "every checkpoint but the fly sits in the middle of a frame slot of its phase",
    arguments: ShowCheckpoint.allCases.filter { $0 != .fly }
  )
  func midFrame(checkpoint: ShowCheckpoint) {
    let offset = checkpoint.offset(in: choreography)
    let slots = offset / choreography.frameDuration
    #expect(abs(slots - slots.rounded(.down) - 0.5) < 0.001, "\(checkpoint) at \(offset) is \(slots) frames in")
    if let duration = choreography.duration(of: checkpoint.phase) {
      #expect(offset < duration, "\(checkpoint) would fall into the next phase")
    } else {
      #expect(offset > choreography.pointDuration, "the point checkpoint waits for the bubble")
    }
  }

  /// The flight ends past the screen's right edge, so it covers a different distance in the
  /// same two seconds on every screen: any later moment would draw the monster somewhere else
  /// on a narrower screen than the one the reference was captured on.
  @Test("the fly checkpoint is drawn before the monster leaves its spot")
  func flyStartsOnTheSpot() {
    #expect(ShowCheckpoint.fly.offset(in: choreography) == .zero)
    let layouts = [1024.0, 1440, 1920, 3440].map { width in
      choreography.layout(
        aim: TargetAim(point: CGPoint(x: 700, y: 400)),
        targetCount: 1,
        screen: CGRect(x: 0, y: 0, width: width, height: 768),
        characterAspect: 1,
        explosionAspect: 1
      )
    }
    #expect(Set(layouts.map(\.stand.x)).count == 1)
    #expect(Set(layouts.map(\.exit.x)).count == layouts.count)
  }

  /// The ceiling `ShippedPackTests.checkpointsFitTheirPhases` enforces on every shipped pack,
  /// proved to bite here rather than only asserted to hold there. `exploding` runs from the impact
  /// frame to the end of the sheet, so a pack that lands its kick late leaves the explosion
  /// checkpoint nowhere to sit; on a 15-frame sheet at 8 fps the last workable `kickImpactFrame`
  /// is 10, which is the Cat pack's, and 11 puts the capture at or past `entered(rescuing)` where
  /// `ShowStage.snapshot` would draw the rescue with no error and no reference to catch it.
  @Test("a late kick pushes the explosion checkpoint out of its phase", arguments: [10, 11])
  func explosionCheckpointCeiling(kickImpactFrame: Int) throws {
    var descriptor = PackDescriptor.defaults
    descriptor.kickImpactFrame = kickImpactFrame
    let choreography = Choreography(pack: descriptor)
    let phase = try #require(choreography.duration(of: .exploding))
    #expect(phase == choreography.sheetDuration - choreography.impactDelay)
    let offset = ShowCheckpoint.explosion.offset(in: choreography)
    #expect(
      (offset < phase) == (kickImpactFrame == 10),
      "kickImpactFrame \(kickImpactFrame): the explosion checkpoint sits at \(offset) of a \(phase) phase"
    )
  }

  @Test("the capture is a 640 x 520 window centred on the target point")
  func captureRect() {
    let rect = ShowCheckpoint.captureRect(around: CGPoint(x: 700, y: 400))
    #expect(rect == CGRect(x: 380, y: 140, width: 640, height: 520))
  }
}
