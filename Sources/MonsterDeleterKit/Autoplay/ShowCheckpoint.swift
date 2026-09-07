import Foundation

/// The six moments of a show the self-test captures to PNG: one per sheet, each a fixed time
/// into its phase, in the middle of a frame slot so a few milliseconds of scheduling jitter
/// never change the frame on screen. The walk is taken where the monster is slowest, so the
/// same jitter moves it by a pixel or two at most; the fly is taken before it moves at all,
/// because the flight ends past the screen's right edge and therefore covers a different
/// distance in the same two seconds on every screen (`Choreography.layout`), which a committed
/// reference cannot hold.
public enum ShowCheckpoint: String, Sendable, Hashable, CaseIterable {
  case walk, point, kick, explosion, rescuer, fly

  /// The capture is this many points wide and high, centred on the target point: room for the
  /// monster beside the target, the bubble over its head, the buttons under its feet and a fan.
  public static let captureSize = CGSize(width: 640, height: 520)

  public var phase: ShowPhase {
    switch self {
    case .walk: return .walking
    case .point: return .asking
    case .kick: return .kicking
    case .explosion: return .exploding
    case .rescuer: return .rescuing
    case .fly: return .flying
    }
  }

  /// `01-walk.png` ... `06-fly.png`.
  public var fileName: String {
    let rank = (Self.allCases.firstIndex(of: self) ?? 0) + 1
    return String(format: "%02d-%@.png", rank, rawValue)
  }

  /// Time into the phase, measured in frame slots of the choreography.
  public func offset(in choreography: Choreography) -> Duration {
    let slots: Double
    switch self {
    case .walk: slots = 31.5  // third walk loop, frame 1, the monster almost at its spot and slow
    case .point: slots = 8.5  // frame 14 held, bubble and buttons up for a second
    case .kick: slots = 2.5  // kick frame 2, before the impact
    case .explosion: slots = 4.5  // explosion frame 4 over kick frame 9
    case .rescuer: slots = 7.5  // rescuer frame 7, the explosion gone
    // Fly frame 0 at the flight's first moment, before the position animation begins: the only
    // moment of the flight that puts the monster in the same place on every screen.
    case .fly: slots = 0
    }
    return choreography.frameDuration * slots
  }

  public static func captureRect(around target: CGPoint) -> CGRect {
    CGRect(
      x: target.x - captureSize.width / 2,
      y: target.y - captureSize.height / 2,
      width: captureSize.width,
      height: captureSize.height
    )
  }
}
