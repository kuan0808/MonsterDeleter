import MonsterDeleterKit

/// A clock the tests move by hand.
final class ManualClock: ShowClock, @unchecked Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration

    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }

  private(set) var now = Instant(offset: .zero)

  func advance(by duration: Duration) {
    now = now.advanced(by: duration)
  }
}
