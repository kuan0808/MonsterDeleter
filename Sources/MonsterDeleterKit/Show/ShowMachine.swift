import Foundation

/// The show's phase machine. Pure: it reads a clock and returns events; it never performs effects.
///
/// Drive it by calling `tick()` whenever `nextDeadline` passes, and `aim(at:)`, `confirm()` or
/// `cancel()` when the user acts. Timed phases advance from their scheduled start, not from the
/// tick time, so late ticks never accumulate drift. A selection of any size plays the one
/// timeline: one walk, one ask, one kick, every item exploding on the impact frame.
public struct ShowMachine<Clock: ShowClock> {
  public let choreography: Choreography
  /// How many items the selection has; at least one.
  public let targetCount: Int
  public private(set) var phase: ShowPhase
  public private(set) var target: CGPoint?

  private let clock: Clock
  private var phaseStart: Clock.Instant
  private var started = false
  private var bubbleAnnounced = false

  /// A machine that will aim first when `target` is `nil` and walk straight in otherwise.
  public init(choreography: Choreography, clock: Clock, target: CGPoint?, targetCount: Int) {
    precondition(targetCount >= 1, "a show needs at least one target")
    self.choreography = choreography
    self.targetCount = targetCount
    self.clock = clock
    self.target = target
    phase = target == nil ? .aiming : .walking
    phaseStart = clock.now
  }

  public var isInteractive: Bool { phase.isInteractive }

  /// Time in the current phase.
  public var elapsedInPhase: Duration { phaseStart.duration(to: clock.now) }

  /// When `tick()` next has something to do, or `nil` while waiting for the user or when over.
  public var nextDeadline: Clock.Instant? {
    if let duration = choreography.duration(of: phase) {
      return phaseStart.advanced(by: duration)
    }
    if phase == .asking, !bubbleAnnounced {
      return phaseStart.advanced(by: choreography.pointDuration)
    }
    return nil
  }

  /// Enters the first phase. Call once.
  public mutating func start() -> [ShowEvent] {
    precondition(!started, "ShowMachine.start() called twice")
    started = true
    return enter(phase)
  }

  /// The user clicked the crosshair on `point`.
  public mutating func aim(at point: CGPoint) -> [ShowEvent] {
    guard started, phase == .aiming else { return [] }
    target = point
    return enter(.entering)
  }

  /// The user pressed either button.
  public mutating func confirm() -> [ShowEvent] {
    guard started, phase == .asking else { return [] }
    return enter(.kicking)
  }

  /// Esc or a click outside. Only interactive phases can be cancelled; the file is untouched.
  public mutating func cancel() -> [ShowEvent] {
    guard started, phase.isInteractive else { return [] }
    return enter(.cancelled)
  }

  /// Advances through every timed phase whose deadline has passed, in order.
  public mutating func tick() -> [ShowEvent] {
    guard started else { return [] }
    let now = clock.now
    var events: [ShowEvent] = []
    while let duration = choreography.duration(of: phase),
      let next = phase.successor,
      phaseStart.advanced(by: duration) <= now
    {
      phaseStart = phaseStart.advanced(by: duration)
      phase = next
      bubbleAnnounced = false
      events.append(.entered(next))
    }
    if phase == .asking, !bubbleAnnounced, phaseStart.advanced(by: choreography.pointDuration) <= now {
      bubbleAnnounced = true
      events.append(.askBubbleDue)
    }
    return events
  }

  private mutating func enter(_ next: ShowPhase) -> [ShowEvent] {
    phase = next
    phaseStart = clock.now
    bubbleAnnounced = false
    return [.entered(next)]
  }
}
