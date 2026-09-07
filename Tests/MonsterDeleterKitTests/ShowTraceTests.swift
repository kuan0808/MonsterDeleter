import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("ShowTrace")
struct ShowTraceTests {
  let timetable = ShowTimetable.confirmed(.standard, confirmDelay: .seconds(2))
  let tolerance = Duration.milliseconds(150)

  /// The phase times of the Phase 7 evidence run, in seconds.
  func evidenceTrace(dropLast: Int = 0) -> ShowTrace {
    var trace = ShowTrace()
    let entries: [(ShowEvent, Double)] = [
      (.entered(.walking), 0.000_032), (.entered(.asking), 4.500_905), (.askBubbleDue, 5.002_109),
      (.entered(.kicking), 7.146_234), (.entered(.exploding), 7.773_326), (.entered(.rescuing), 9.022_225),
      (.entered(.flying), 10.898_328), (.entered(.done), 12.898_342),
    ]
    for (event, seconds) in entries.dropLast(dropLast) {
      trace.record(event, at: .seconds(seconds))
    }
    return trace
  }

  @Test("the evidence run passes: every transition within its window")
  func evidenceRunPasses() {
    #expect(evidenceTrace().problems(against: timetable, tolerance: tolerance).isEmpty)
  }

  @Test("a show that stopped early names the missing event")
  func missingEvent() {
    let problems = evidenceTrace(dropLast: 2).problems(against: timetable, tolerance: tolerance)
    #expect(problems.count == 1)
    #expect(problems[0].contains("entered(flying)"))
    #expect(problems[0].contains("missing"))
  }

  @Test("an event out of order names what was expected and what came")
  func wrongOrder() {
    var trace = ShowTrace()
    trace.record(.entered(.walking), at: .zero)
    trace.record(.askBubbleDue, at: .seconds(4.5))
    let problems = trace.problems(against: timetable, tolerance: tolerance)
    #expect(problems.first?.contains("entered(asking)") == true)
    #expect(problems.first?.contains("askBubbleDue") == true)
  }

  @Test("a transition outside its window is reported with the measured gap")
  func lateTransition() {
    var trace = ShowTrace()
    trace.record(.entered(.walking), at: .zero)
    trace.record(.entered(.asking), at: .seconds(4.9))
    let problems = trace.problems(against: timetable, tolerance: tolerance)
    #expect(problems.count >= 1)
    #expect(problems[0].contains("entered(asking)"))
    #expect(problems[0].contains("4.9"))
    #expect(problems[0].contains("4.5"))
  }

  @Test("the button press may be late by its slack but not early")
  func confirmSlack() {
    var late = ShowTrace()
    late.record(.entered(.walking), at: .zero)
    late.record(.entered(.asking), at: .seconds(4.5))
    late.record(.askBubbleDue, at: .seconds(5))
    late.record(.entered(.kicking), at: .seconds(7.6))
    let lateProblems = late.problems(against: timetable, tolerance: tolerance)
    #expect(!lateProblems.contains { $0.contains("entered(kicking)") && $0.contains("7.6") })

    var early = late
    early = ShowTrace()
    early.record(.entered(.walking), at: .zero)
    early.record(.entered(.asking), at: .seconds(4.5))
    early.record(.askBubbleDue, at: .seconds(5))
    early.record(.entered(.kicking), at: .seconds(6.5))
    let earlyProblems = early.problems(against: timetable, tolerance: tolerance)
    #expect(earlyProblems.contains { $0.contains("entered(kicking)") })
  }

  @Test("an event after the end of the timetable is a problem")
  func extraEvent() {
    var trace = evidenceTrace()
    trace.record(.entered(.walking), at: .seconds(13))
    let problems = trace.problems(against: timetable, tolerance: tolerance)
    #expect(problems.count == 1)
    #expect(problems[0].contains("unexpected"))
  }

  @Test("an empty trace reports the first missing event only")
  func empty() {
    let problems = ShowTrace().problems(against: timetable, tolerance: tolerance)
    #expect(problems == ["missing entered(walking)"])
  }
}
