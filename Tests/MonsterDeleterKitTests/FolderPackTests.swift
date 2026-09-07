import CoreGraphics
import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("FolderPack")
struct FolderPackTests {
  let root: URL
  let folder: URL
  let cache: SheetCache

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "FolderPackTests-\(UUID().uuidString)")
    folder = root.appending(path: "kaiju")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    cache = SheetCache(directory: root.appending(path: "cache"))
  }

  private func write(manifest: String) throws {
    try Data(manifest.utf8).write(to: folder.appending(path: "pack.json"))
  }

  @Test("declared files are read from the folder, the rest come from the built-in pack")
  func declaredAndFallback() throws {
    try write(
      manifest: #"{"name": "Kaiju", "sheets": {"walk": {"file": "w.png"}}, "audio": {"voice": {"file": "v.wav"}}}"#
    )
    try TestImages.writeSheet(to: folder.appending(path: "w.png"), cell: CGSize(width: 9, height: 16), gray: 0.2)
    let voice = Data("RIFF fake".utf8)
    try voice.write(to: folder.appending(path: "v.wav"))
    let pack = try FolderPack(folder: folder, cache: cache)
    #expect(pack.descriptor.name == "Kaiju")
    let walk = try pack.sheet(for: .walk)
    #expect(walk.height == 3 * 500, "frames are twice the 250 pt character height")
    #expect(walk.width == 5 * 281, "9 x 16 cells keep their aspect")
    #expect(TestImages.firstRed(of: walk) == 51)
    let kick = try pack.sheet(for: .kick)
    #expect(CGFloat(kick.width) == PlaceholderSheetRenderer.characterFrameSize.width * 5, "the built-in kick sheet")
    #expect(try pack.audio(for: .voice) == voice)
    #expect(try pack.audio(for: .bgm) == ToneSynthesizer.backgroundLoop())
    #expect(pack.warnings.isEmpty)
  }

  @Test("a default-named file in the folder is used without being declared")
  func defaultNamesAreFound() throws {
    try write(manifest: "{}")
    try TestImages.writeSheet(to: folder.appending(path: "kick.png"), cell: CGSize(width: 9, height: 16), gray: 0.2)
    let bgm = Data("RIFF bgm".utf8)
    try bgm.write(to: folder.appending(path: "bgm.wav"))
    let pack = try FolderPack(folder: folder, cache: cache)
    #expect(try pack.sheet(for: .kick).height == 1500)
    #expect(try pack.audio(for: .bgm) == bgm)
    #expect(pack.descriptor.name == "kaiju", "an unnamed pack takes its folder's name")
  }

  @Test("a grid declared for a sheet the folder does not ship does not warp the built-in sheet")
  func substitutedSheetKeepsThePlaceholderGrid() throws {
    try write(manifest: #"{"sheets": {"walk": {"columns": 3, "rows": 2}}}"#)
    let pack = try FolderPack(folder: folder, cache: cache)
    #expect(pack.descriptor.sheets[.walk] == SheetDescriptor(file: "walk.png", columns: 5, rows: 3))
    let loaded = try LoadedPack(source: pack)
    #expect(loaded.frames(for: .walk).count == 15)
    #expect(loaded.frames(for: .walk).first?.width == Int(PlaceholderSheetRenderer.characterFrameSize.width))
    #expect(loaded.frames(for: .walk).first?.height == Int(PlaceholderSheetRenderer.characterFrameSize.height))
  }

  @Test("a dropped point grid takes its default frame range from the placeholder sheet")
  func substitutedPointGridRecomputesTheDefaultRange() throws {
    try write(manifest: #"{"sheets": {"point": {"columns": 2, "rows": 2}}}"#)
    let pack = try FolderPack(folder: folder, cache: cache)
    #expect(pack.descriptor.pointFrames == 11...14)
    #expect(
      pack.warnings.contains { $0.hasPrefix("sheets.point: the 2x2 grid is ignored") },
      "the dropped grid is not in the log: \(pack.warnings)"
    )
  }

  @Test("an author's point frames survive a dropped grid while they still fit")
  func substitutedPointGridKeepsAnExplicitRange() throws {
    try write(manifest: #"{"sheets": {"point": {"columns": 4, "rows": 4}}, "pointFrames": [12, 13]}"#)
    let pack = try FolderPack(folder: folder, cache: cache)
    #expect(pack.descriptor.pointFrames == 12...13)
  }

  @Test("an impact frame the placeholder sheet has no room for falls back to the default")
  func substitutedKickGridRecomputesAnOutOfRangeImpactFrame() throws {
    try write(manifest: #"{"sheets": {"kick": {"columns": 5, "rows": 5}}, "kickImpactFrame": 20}"#)
    let pack = try FolderPack(folder: folder, cache: cache)
    #expect(pack.descriptor.kickImpactFrame == 5)
    #expect(pack.descriptor.sheets[.kick]?.frameCount == 15)
  }

  @Test("a grid declared for a sheet the folder does ship still slices that grid")
  func presentSheetKeepsItsDeclaredGrid() throws {
    try write(manifest: #"{"sheets": {"walk": {"columns": 3, "rows": 2}}}"#)
    try TestImages.writeSheet(to: folder.appending(path: "walk.png"), columns: 3, rows: 2)
    let pack = try FolderPack(folder: folder, cache: cache)
    #expect(pack.descriptor.sheets[.walk] == SheetDescriptor(file: "walk.png", columns: 3, rows: 2))
    let loaded = try LoadedPack(source: pack)
    #expect(loaded.frames(for: .walk).count == 6)
    #expect(loaded.frames(for: .walk).first?.height == 500, "frames are twice the 250 pt character height")
  }

  @Test("a declared file that is missing is an error, not a silent fallback")
  func declaredMissingFileThrows() throws {
    try write(manifest: #"{"sheets": {"walk": {"file": "nope.png"}}, "audio": {"bgm": {"file": "nope.mp3"}}}"#)
    let pack = try FolderPack(folder: folder, cache: cache)
    #expect(throws: PackError.missingFile("nope.png")) { try pack.sheet(for: .walk) }
    #expect(throws: PackError.missingFile("nope.mp3")) { try pack.audio(for: .bgm) }
    #expect(throws: PackError.missingFile("nope.png")) { try LoadedPack(source: pack) }
  }

  @Test("the explosion is scaled to twice the explosion height")
  func explosionHeight() throws {
    try write(manifest: #"{"explosionHeight": 100, "sheets": {"explosion": {"file": "boom.png"}}}"#)
    try TestImages.writeSheet(to: folder.appending(path: "boom.png"), cell: CGSize(width: 3, height: 4))
    let pack = try FolderPack(folder: folder, cache: cache)
    let loaded = try LoadedPack(source: pack)
    #expect(loaded.frames(for: .explosion).count == 15)
    #expect(loaded.frames(for: .explosion).first?.height == 200)
    #expect(loaded.aspect(of: .explosion) == 0.75)
  }

  @Test("a folder without pack.json is not a pack")
  func missingManifest() {
    #expect(throws: PackError.notAPack("kaiju")) { try FolderPack(folder: folder, cache: cache) }
  }

  @Test("manifest warnings are carried so the log can name them")
  func warningsCarried() throws {
    try write(manifest: #"{"framesPerSecond": "fast"}"#)
    let pack = try FolderPack(folder: folder, cache: cache)
    #expect(pack.warnings.count == 1)
    #expect(pack.descriptor.framesPerSecond == 8)
  }
}
