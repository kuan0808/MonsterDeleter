import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("ShowTimetable")
struct ShowTimetableTests {
  @Test("a confirmed show lists every event with the table's gap and slack only for the button press")
  func confirmed() {
    let steps = ShowTimetable.confirmed(.standard, confirmDelay: .seconds(2)).steps
    #expect(
      steps.map(\.event) == [
        .entered(.walking), .entered(.asking), .askBubbleDue, .entered(.kicking), .entered(.exploding),
        .entered(.rescuing), .entered(.flying), .entered(.done),
      ]
    )
    #expect(
      steps.map(\.after) == [
        .zero, .milliseconds(4500), .milliseconds(500), .seconds(2), .milliseconds(625), .milliseconds(1250),
        .milliseconds(1875), .seconds(2),
      ]
    )
    #expect(steps.map(\.slack) == [.zero, .zero, .zero, .milliseconds(500), .zero, .zero, .zero, .zero])
  }

  @Test("an Esc during the ask ends in cancelled and nothing explodes")
  func cancelled() {
    let steps = ShowTimetable.cancelled(.standard, cancelDelay: .milliseconds(250)).steps
    #expect(steps.map(\.event) == [.entered(.walking), .entered(.asking), .askBubbleDue, .entered(.cancelled)])
    #expect(steps[3].after == .milliseconds(250))
    #expect(steps[3].slack == .milliseconds(500))
  }
}
