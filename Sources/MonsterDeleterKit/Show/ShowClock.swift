/// The clock the show machine reads. `ContinuousClock` in the app; a hand-advanced clock in tests.
public protocol ShowClock {
  associatedtype Instant: InstantProtocol where Instant.Duration == Duration
  var now: Instant { get }
}

extension ContinuousClock: ShowClock {}
