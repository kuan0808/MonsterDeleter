import Foundation

/// The events one show reported, each with its time since the summon, and the check the
/// self-test runs on them: the timetable's events in order, each transition within its window.
public struct ShowTrace: Sendable, Hashable {
  public struct Entry: Sendable, Hashable {
    public var event: ShowEvent
    public var time: Duration
  }

  public private(set) var entries: [Entry] = []

  public init() {}

  public mutating func record(_ event: ShowEvent, at time: Duration) {
    entries.append(Entry(event: event, time: time))
  }

  /// Every way the trace departs from `timetable`, one line each; empty when the show ran to
  /// the table. A missing event stops the walk, since everything after it is missing too.
  public func problems(against timetable: ShowTimetable, tolerance: Duration) -> [String] {
    var problems: [String] = []
    var previous = Duration.zero
    for (index, step) in timetable.steps.enumerated() {
      guard index < entries.count else {
        problems.append("missing \(Self.name(step.event))")
        return problems
      }
      let entry = entries[index]
      guard entry.event == step.event else {
        problems.append(
          "expected \(Self.name(step.event)), got \(Self.name(entry.event)) at \(Self.seconds(entry.time))"
        )
        return problems
      }
      let gap = entry.time - previous
      if gap < step.after - tolerance || gap > step.after + tolerance + step.slack {
        problems.append(
          "\(Self.name(step.event)) came \(Self.seconds(gap)) after the previous event, table says \(Self.seconds(step.after))"
        )
      }
      previous = entry.time
    }
    for entry in entries.dropFirst(timetable.steps.count) {
      problems.append("unexpected \(Self.name(entry.event)) at \(Self.seconds(entry.time))")
    }
    return problems
  }

  /// `entered(walking)`, `askBubbleDue`: the event without its module and type prefixes.
  public static func name(_ event: ShowEvent) -> String {
    switch event {
    case .entered(let phase): return "entered(\(phase.rawValue))"
    case .askBubbleDue: return "askBubbleDue"
    }
  }

  /// The self-test's log is read by a script and quoted in the evidence, so its numbers are
  /// written the same on every Mac rather than in the user's locale (a German one would print
  /// `4,501 s`).
  public static let logLocale = Locale(identifier: "en_US_POSIX")

  /// `4.501 s`, to the millisecond.
  public static func seconds(_ duration: Duration) -> String {
    let parts = duration.components
    let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    let written = seconds.formatted(.number.precision(.fractionLength(3)).grouping(.never).locale(logLocale))
    return "\(written) s"
  }
}
