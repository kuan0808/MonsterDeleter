/// The events one autoplay show must report, in order, with the gap the choreography promises
/// between each and the one before. Only the step that waits for the autoplay's own answer
/// carries slack: `Task.sleep` may wake late, the render server never does.
public struct ShowTimetable: Sendable, Hashable {
  public struct Step: Sendable, Hashable {
    public var event: ShowEvent
    /// Time after the previous step.
    public var after: Duration
    /// How much later than `after` the step may still come, on top of the tolerance.
    public var slack: Duration

    public init(event: ShowEvent, after: Duration, slack: Duration = .zero) {
      self.event = event
      self.after = after
      self.slack = slack
    }
  }

  /// How late the answer to the ask may come after its delay.
  public static let answerSlack = Duration.milliseconds(500)

  public var steps: [Step]

  public init(steps: [Step]) {
    self.steps = steps
  }

  /// A show with a known target that the button confirms `confirmDelay` after the bubble.
  public static func confirmed(_ choreography: Choreography, confirmDelay: Duration) -> ShowTimetable {
    var steps = ask(choreography)
    steps.append(Step(event: .entered(.kicking), after: confirmDelay, slack: answerSlack))
    var phase = ShowPhase.kicking
    while let duration = choreography.duration(of: phase), let next = phase.successor {
      steps.append(Step(event: .entered(next), after: duration))
      phase = next
    }
    return ShowTimetable(steps: steps)
  }

  /// A show with a known target that Esc cancels `cancelDelay` after the bubble.
  public static func cancelled(_ choreography: Choreography, cancelDelay: Duration) -> ShowTimetable {
    var steps = ask(choreography)
    steps.append(Step(event: .entered(.cancelled), after: cancelDelay, slack: answerSlack))
    return ShowTimetable(steps: steps)
  }

  private static func ask(_ choreography: Choreography) -> [Step] {
    [
      Step(event: .entered(.walking), after: .zero),
      Step(event: .entered(.asking), after: choreography.walkDuration),
      Step(event: .askBubbleDue, after: choreography.pointDuration),
    ]
  }
}
