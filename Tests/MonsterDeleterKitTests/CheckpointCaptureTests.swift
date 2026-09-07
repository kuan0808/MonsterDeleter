import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("CheckpointCapture")
struct CheckpointCaptureTests {
  let choreography = Choreography.standard
  let animationStart: CFTimeInterval = 12_345.5

  func seconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }

  /// The moment the checkpoint asks for, and the sprite frame of its sheet showing then.
  func moment(_ checkpoint: ShowCheckpoint) -> CFTimeInterval {
    animationStart + seconds(checkpoint.offset(in: choreography))
  }

  func frame(at time: CFTimeInterval) -> Int {
    Int(((time - animationStart) / seconds(choreography.frameDuration)).rounded(.down))
  }

  @Test(
    "a capture the machine wakes late still draws the checkpoint's own frame",
    arguments: ShowCheckpoint.allCases,
    [0, 0.07, 0.2, 0.5]
  )
  func lateWake(checkpoint: ShowCheckpoint, lateness: Double) {
    let woke = moment(checkpoint) + lateness
    let capture = CheckpointCapture(
      checkpoint,
      animationStart: animationStart,
      now: woke,
      choreography: choreography
    )
    #expect(capture.showTime == moment(checkpoint))
    #expect(capture.waits == .zero)
    #expect(frame(at: capture.showTime) == Int((checkpoint.offset(in: choreography) / choreography.frameDuration)))
    let slot = seconds(choreography.frameDuration)
    let intoSlot = seconds(checkpoint.offset(in: choreography)).truncatingRemainder(dividingBy: slot)
    if intoSlot + lateness >= slot {
      // What the capture used to draw: whatever was on screen when it woke, a frame slot on.
      #expect(frame(at: woke) > frame(at: capture.showTime))
    }
  }

  @Test("a capture that arrives before the moment waits for it", arguments: ShowCheckpoint.allCases)
  func earlyWake(checkpoint: ShowCheckpoint) {
    let capture = CheckpointCapture(
      checkpoint,
      animationStart: animationStart,
      now: moment(checkpoint) - 0.04,
      choreography: choreography
    )
    #expect(capture.showTime == moment(checkpoint))
    #expect(abs(seconds(capture.waits) - 0.04) < 0.001)
    let waited = CheckpointCapture(
      checkpoint,
      animationStart: animationStart,
      now: capture.showTime,
      choreography: choreography
    )
    #expect(waited.waits == .zero)
  }
}
