import Testing

@testable import MonsterDeleterKit

@Suite("LoadFailureQueue")
struct LoadFailureQueueTests {
  private let first = LoadFailureQueue.Report(title: "Cannot load the pack \"Kaiju\"", message: "missingFile")
  private let second = LoadFailureQueue.Report(title: "Cannot load the pack \"Sea\"", message: "cannotDecode")

  @Test("a failure with no show on screen is presented at once")
  func immediate() {
    var queue = LoadFailureQueue()
    #expect(queue.enqueue(first, showIsRunning: false) == [first])
    #expect(queue.drain().isEmpty, "it was presented, not held")
  }

  @Test("a failure during a show is held and delivered once when the show finishes")
  func deferredUntilTheShowEnds() {
    var queue = LoadFailureQueue()
    #expect(queue.enqueue(first, showIsRunning: true).isEmpty)
    #expect(queue.enqueue(second, showIsRunning: true).isEmpty)
    #expect(queue.drain() == [first, second])
    #expect(queue.drain().isEmpty, "a second show does not repeat them")
  }

  @Test("a held failure comes out with the next one presented after the show")
  func heldFailureJoinsTheNext() {
    var queue = LoadFailureQueue()
    #expect(queue.enqueue(first, showIsRunning: true).isEmpty)
    #expect(queue.enqueue(second, showIsRunning: false) == [first, second])
    #expect(queue.drain().isEmpty)
  }
}
