import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("TargetPointResolver")
struct TargetPointResolverTests {
  let now = ContinuousClock.now
  let point = CGPoint(x: 1584, y: 211)

  @Test("no sample means the crosshair")
  func noSample() {
    #expect(TargetPointResolver.resolve(nil, now: now) == nil)
  }

  @Test("a fresh right-click is the target")
  func freshSample() {
    let sample = TargetSample(point: point, takenAt: now.advanced(by: .seconds(-2)))
    #expect(TargetPointResolver.resolve(sample, now: now) == point)
  }

  @Test("a sample at the age limit still counts")
  func atLimit() {
    let sample = TargetSample(point: point, takenAt: now.advanced(by: .zero - TargetPointResolver.maxSampleAge))
    #expect(TargetPointResolver.resolve(sample, now: now) == point)
  }

  @Test("a stale sample means the crosshair, never the mouse")
  func staleSample() {
    let sample = TargetSample(point: point, takenAt: now.advanced(by: .seconds(-16)))
    #expect(TargetPointResolver.resolve(sample, now: now) == nil)
  }

  @Test("a sample from the future is rejected")
  func futureSample() {
    let sample = TargetSample(point: point, takenAt: now.advanced(by: .seconds(1)))
    #expect(TargetPointResolver.resolve(sample, now: now) == nil)
  }
}
