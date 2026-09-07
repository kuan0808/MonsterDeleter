import CoreGraphics
import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("SnapshotComparison")
struct SnapshotComparisonTests {
  @Test("identical images do not differ at all")
  func identical() throws {
    let a = try #require(TestImages.bitmap(width: 20, height: 10) { x, _ in x < 10 ? 0.2 : 0.9 })
    let b = try #require(TestImages.bitmap(width: 20, height: 10) { x, _ in x < 10 ? 0.2 : 0.9 })
    #expect(SnapshotComparison.mismatch(a, b) == 0)
  }

  @Test("the mismatch is the share of pixels that differ by more than the threshold in any channel")
  func fraction() throws {
    let a = try #require(TestImages.bitmap(width: 20, height: 10) { _, _ in 0.5 })
    let b = try #require(TestImages.bitmap(width: 20, height: 10) { x, _ in x < 5 ? 1 : 0.5 })
    #expect(SnapshotComparison.mismatch(a, b) == 0.25)
  }

  @Test("a difference under the threshold is noise, not a mismatch")
  func noise() throws {
    let a = try #require(TestImages.bitmap(width: 8, height: 8) { _, _ in 0.5 })
    let b = try #require(TestImages.bitmap(width: 8, height: 8) { _, _ in 0.5 + 20.0 / 255 })
    #expect(SnapshotComparison.mismatch(a, b) == 0)
    #expect(SnapshotComparison.mismatch(a, b, threshold: 10) == 1)
  }

  @Test("images of different sizes cannot be compared")
  func sizeMismatch() throws {
    let a = try #require(TestImages.bitmap(width: 8, height: 8) { _, _ in 0.5 })
    let b = try #require(TestImages.bitmap(width: 8, height: 9) { _, _ in 0.5 })
    #expect(SnapshotComparison.mismatch(a, b) == nil)
  }

  @Test("a PNG survives the round trip through disk")
  func pngRoundTrip() throws {
    let a = try #require(TestImages.bitmap(width: 6, height: 4) { x, y in (x + y) % 2 == 0 ? 0 : 1 })
    let url = FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try PNGFile.write(a, to: url)
    let b = try #require(PNGFile.read(url))
    #expect(SnapshotComparison.mismatch(a, b) == 0)
    #expect(PNGFile.read(url.appending(path: "missing")) == nil)
  }
}
