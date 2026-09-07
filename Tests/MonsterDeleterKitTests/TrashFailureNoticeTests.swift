import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("TrashFailureNotice copy")
struct TrashFailureNoticeTests {
  let good = URL(fileURLWithPath: "/tmp/good.txt")
  let locked = URL(fileURLWithPath: "/tmp/locked.txt")
  let missing = URL(fileURLWithPath: "/tmp/sub/missing")

  @Test("one item that stayed put is named in the title")
  func single() {
    let outcome = TrashOutcome(trashed: [:], failures: [.init(url: locked, message: "No permission.")])
    #expect(TrashFailureNotice.title(for: outcome) == "The monster could not trash “locked.txt”")
    #expect(TrashFailureNotice.body(for: outcome) == "No permission.")
  }

  @Test("several failures are counted against the selection and listed one per line")
  func several() {
    let outcome = TrashOutcome(
      trashed: [good: good],
      failures: [.init(url: locked, message: "No permission."), .init(url: missing, message: "Gone.")]
    )
    #expect(TrashFailureNotice.title(for: outcome) == "The monster could not trash 2 of 3 items")
    #expect(TrashFailureNotice.body(for: outcome) == "locked.txt: No permission.\nmissing: Gone.")
  }

  func outcome(failureCount: Int) -> TrashOutcome {
    TrashOutcome(
      trashed: [:],
      failures: (0..<failureCount).map {
        .init(url: URL(fileURLWithPath: "/tmp/item\($0).txt"), message: "No permission.")
      }
    )
  }

  @Test("a long list of failures is cut to five lines and a count of the rest")
  func cappedList() {
    let lines = TrashFailureNotice.body(for: outcome(failureCount: 8)).components(separatedBy: "\n")
    #expect(lines.count == 6)
    #expect(Array(lines.dropLast()) == (0..<5).map { "item\($0).txt: No permission." })
    #expect(lines.last == "and 3 more")
  }

  @Test("a list that fits is listed whole, with no count line")
  func uncappedList() {
    let lines = TrashFailureNotice.body(for: outcome(failureCount: 5)).components(separatedBy: "\n")
    #expect(lines.count == 5)
    #expect(lines.last == "item4.txt: No permission.")
  }
}
