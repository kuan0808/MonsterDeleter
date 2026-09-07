import CoreGraphics
import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("SheetCache")
struct SheetCacheTests {
  let root: URL
  let cache: SheetCache
  let sheetFile: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "SheetCacheTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    cache = SheetCache(directory: root.appending(path: "cache"))
    sheetFile = root.appending(path: "walk.png")
  }

  @Test("the first use scales the sheet so each frame is the requested height and keeps a copy")
  func firstUseScalesAndStores() throws {
    try TestImages.writeSheet(to: sheetFile, cell: CGSize(width: 4, height: 6), gray: 0.2)
    let scaled = try cache.sheet(for: .walk, at: sheetFile, columns: 5, rows: 3, frameHeight: 12)
    #expect(scaled.width == 40, "4 x 6 cells become 8 x 12 at double height")
    #expect(scaled.height == 36)
    #expect(TestImages.firstRed(of: scaled) == 51)
    let cached = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
    #expect(cached.count == 1)
    #expect(cached[0].hasPrefix("walk-") && cached[0].hasSuffix(".png"))
  }

  @Test("a sheet whose modification date has not changed is served from the cache")
  func unchangedDateHitsCache() throws {
    try TestImages.writeSheet(to: sheetFile, gray: 0.2)
    let stamp = Date(timeIntervalSince1970: 1_700_000_000)
    try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: sheetFile.path)
    _ = try cache.sheet(for: .walk, at: sheetFile, columns: 5, rows: 3, frameHeight: 12)
    try TestImages.writeSheet(to: sheetFile, gray: 1.0)
    try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: sheetFile.path)
    let again = try cache.sheet(for: .walk, at: sheetFile, columns: 5, rows: 3, frameHeight: 12)
    #expect(TestImages.firstRed(of: again) == 51, "the old pixels, because the date says nothing changed")
  }

  @Test("a new modification date replaces the cached copy")
  func changedDateInvalidates() throws {
    try TestImages.writeSheet(to: sheetFile, gray: 0.2)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
      ofItemAtPath: sheetFile.path
    )
    _ = try cache.sheet(for: .walk, at: sheetFile, columns: 5, rows: 3, frameHeight: 12)
    try TestImages.writeSheet(to: sheetFile, gray: 1.0)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_700_000_001)],
      ofItemAtPath: sheetFile.path
    )
    let fresh = try cache.sheet(for: .walk, at: sheetFile, columns: 5, rows: 3, frameHeight: 12)
    #expect(TestImages.firstRed(of: fresh) == 255)
    let cached = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
    #expect(cached.count == 1, "the stale copy is gone: \(cached)")
  }

  @Test("a changed grid or frame height is a different cache entry")
  func gridAndHeightKeyTheEntry() throws {
    try TestImages.writeSheet(to: sheetFile, gray: 0.2)
    _ = try cache.sheet(for: .walk, at: sheetFile, columns: 5, rows: 3, frameHeight: 12)
    let taller = try cache.sheet(for: .walk, at: sheetFile, columns: 5, rows: 3, frameHeight: 24)
    #expect(taller.height == 72)
    let cached = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
    #expect(cached.count == 1)
    #expect(cached[0].contains("-24.png"))
  }

  @Test("a missing or undecodable sheet file is an error, not a crash")
  func missingSheetThrows() throws {
    #expect(throws: PackError.cannotDecode("walk.png")) {
      try cache.sheet(for: .walk, at: sheetFile, columns: 5, rows: 3, frameHeight: 12)
    }
    try Data("not a png".utf8).write(to: sheetFile)
    #expect(throws: PackError.cannotDecode("walk.png")) {
      try cache.sheet(for: .walk, at: sheetFile, columns: 5, rows: 3, frameHeight: 12)
    }
  }
}
