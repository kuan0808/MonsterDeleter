import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("TrashOutcome")
struct TrashOutcomeTests {
  let good = URL(fileURLWithPath: "/tmp/good.txt")
  let missing = URL(fileURLWithPath: "/tmp/missing.txt")

  @Test("no error means no failures")
  func success() {
    let outcome = TrashOutcome(
      requested: [good],
      trashed: [good: URL(fileURLWithPath: "/Users/me/.Trash/good.txt")],
      error: nil
    )
    #expect(outcome.failures.isEmpty)
    #expect(outcome.trashed.count == 1)
  }

  @Test("per-item errors come from NSMultipleUnderlyingErrorsKey with their URL")
  func perItemErrors() {
    let item = NSError(
      domain: NSCocoaErrorDomain,
      code: 4,
      userInfo: [NSURLErrorKey: missing, NSLocalizedDescriptionKey: "The file “missing.txt” doesn’t exist."]
    )
    let batch = NSError(
      domain: NSCocoaErrorDomain,
      code: 512,
      userInfo: [
        NSMultipleUnderlyingErrorsKey: [item], NSLocalizedDescriptionKey: "Some files could not be moved to the trash.",
      ]
    )
    let outcome = TrashOutcome(requested: [good, missing], trashed: [good: good], error: batch)
    #expect(outcome.failures == [TrashOutcome.Failure(url: missing, message: "The file “missing.txt” doesn’t exist.")])
  }

  @Test("every requested item is either trashed or listed as a failure")
  func everyItemAccountedFor() {
    let locked = URL(fileURLWithPath: "/tmp/locked.txt")
    let listed = NSError(
      domain: NSCocoaErrorDomain,
      code: 513,
      userInfo: [NSURLErrorKey: locked, NSLocalizedDescriptionKey: "“locked.txt” couldn’t be moved to the trash."]
    )
    let anonymous = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "Gone."])
    let batch = NSError(
      domain: NSCocoaErrorDomain,
      code: 512,
      userInfo: [
        NSMultipleUnderlyingErrorsKey: [listed, anonymous],
        NSLocalizedDescriptionKey: "Some files could not be moved to the trash.",
      ]
    )
    let outcome = TrashOutcome(requested: [good, locked, missing], trashed: [good: good], error: batch)
    #expect(
      outcome.failures == [
        TrashOutcome.Failure(url: locked, message: "“locked.txt” couldn’t be moved to the trash."),
        TrashOutcome.Failure(url: missing, message: "Some files could not be moved to the trash."),
      ]
    )
  }

  @Test("an error without per-item details blames every item that was not trashed")
  func flatError() {
    let error = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSLocalizedDescriptionKey: "No permission."])
    let outcome = TrashOutcome(requested: [good, missing], trashed: [good: good], error: error)
    #expect(outcome.failures == [TrashOutcome.Failure(url: missing, message: "No permission.")])
  }
}
