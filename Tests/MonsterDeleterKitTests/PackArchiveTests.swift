import CoreGraphics
import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("PackArchive")
struct PackArchiveTests {
  let root: URL
  let packs: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "PackArchiveTests-\(UUID().uuidString)")
    packs = root.appending(path: "packs")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  private func png() throws -> Data {
    let url = root.appending(path: "\(UUID().uuidString).png")
    try TestImages.writeSheet(to: url)
    return try Data(contentsOf: url)
  }

  private func zip(_ name: String, _ entries: [(name: String, data: Data)]) throws -> URL {
    let url = root.appending(path: name)
    try TestZip.write(entries, to: url)
    return url
  }

  @Test("a zip with pack.json and the sheets it names installs under the zip's name")
  func goodZip() throws {
    let manifest = #"{"name": "Kaiju", "sheets": {"walk": {"file": "walk.png"}}}"#
    let url = try zip("Kaiju Pack.zip", [("pack.json", Data(manifest.utf8)), ("walk.png", try png())])
    let folder = try PackArchive(url: url).install(into: packs)
    #expect(folder == packs.appending(path: "Kaiju-Pack"))
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "pack.json").path))
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "walk.png").path))
    let cache = SheetCache(directory: root.appending(path: "cache"))
    #expect(try FolderPack(folder: folder, cache: cache).descriptor.name == "Kaiju")
  }

  @Test("a Finder-made zip wraps the pack in a folder and adds __MACOSX; both are unwrapped")
  func finderZip() throws {
    let entries: [(name: String, data: Data)] = [
      ("kaiju/", Data()),
      ("kaiju/pack.json", Data("{}".utf8)),
      ("kaiju/kick.png", try png()),
      ("__MACOSX/kaiju/._pack.json", Data([0, 5, 22])),
    ]
    let url = try zip("kaiju.zip", entries)
    let folder = try PackArchive(url: url).install(into: packs)
    #expect(folder == packs.appending(path: "kaiju"))
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "kick.png").path))
    #expect(!FileManager.default.fileExists(atPath: packs.appending(path: "__MACOSX").path))
  }

  @Test("installing again replaces the pack")
  func reinstallReplaces() throws {
    let first = try zip("kaiju.zip", [("pack.json", Data(#"{"name": "One"}"#.utf8)), ("old.txt", Data())])
    _ = try PackArchive(url: first).install(into: packs)
    let second = try zip("kaiju.zip", [("pack.json", Data(#"{"name": "Two"}"#.utf8))])
    let folder = try PackArchive(url: second).install(into: packs)
    let json = try Data(contentsOf: folder.appending(path: "pack.json"))
    #expect(String(decoding: json, as: UTF8.self).contains("Two"))
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "old.txt").path))
  }

  @Test("a zip without pack.json is rejected before anything is copied")
  func noManifest() throws {
    let url = try zip("art.zip", [("walk.png", try png()), ("readme.txt", Data("hi".utf8))])
    #expect(throws: PackInstallError.noManifest) { try PackArchive(url: url).install(into: packs) }
    #expect(!FileManager.default.fileExists(atPath: packs.path))
  }

  @Test("a zip with a path traversal entry is rejected", arguments: ["../evil.txt", "a/../../evil.txt", "/etc/evil"])
  func pathTraversal(entry: String) throws {
    let url = try zip("evil.zip", [("pack.json", Data("{}".utf8)), (entry, Data("x".utf8))])
    #expect(throws: PackInstallError.unsafeEntry(entry)) { try PackArchive(url: url).install(into: packs) }
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "evil.txt").path))
    #expect(!FileManager.default.fileExists(atPath: packs.path))
  }

  @Test("a manifest that names a sheet the zip lacks is rejected")
  func missingReferencedSheet() throws {
    let manifest = #"{"sheets": {"walk": {"file": "walk.png"}, "kick": {"file": "kick.png"}}}"#
    let url = try zip("half.zip", [("pack.json", Data(manifest.utf8)), ("walk.png", try png())])
    #expect(throws: PackInstallError.missingFile("kick.png")) { try PackArchive(url: url).install(into: packs) }
  }

  @Test("a manifest that is not a JSON object is rejected")
  func invalidManifest() throws {
    let url = try zip("bad.zip", [("pack.json", Data("[1]".utf8))])
    #expect(throws: PackInstallError.invalidManifest) { try PackArchive(url: url).install(into: packs) }
  }

  @Test("something that is not a zip is rejected")
  func notAZip() throws {
    let url = root.appending(path: "notes.zip")
    try Data("just text".utf8).write(to: url)
    #expect(throws: PackInstallError.notAZip) { try PackArchive(url: url).install(into: packs) }
  }

  @Test("an archive with more files than a pack may have is rejected before anything is copied")
  func tooManyEntries() throws {
    let entries = (0...PackArchive.maximumEntryCount).map { (name: "f\($0).txt", data: Data()) }
    let url = try zip("many.zip", entries)
    #expect(throws: PackInstallError.tooManyEntries(entries.count)) { try PackArchive(url: url).install(into: packs) }
    #expect(!FileManager.default.fileExists(atPath: packs.path))
  }

  @Test("the uncompressed size comes from the archive's own listing")
  func uncompressedSize() throws {
    let sheet = try png()
    let url = try zip("sized.zip", [("pack.json", Data("{}".utf8)), ("walk.png", sheet)])
    #expect(try PackArchive(url: url).uncompressedBytes() == 2 + sheet.count)
  }

  @Test("an archive that unpacks past the size cap is rejected")
  func sizeCap() throws {
    let archive = PackArchive(url: root.appending(path: "none.zip"))
    try archive.checkLimits(entryCount: 3, uncompressedBytes: PackArchive.maximumUncompressedBytes)
    #expect(throws: PackInstallError.archiveTooLarge(PackArchive.maximumUncompressedBytes + 1)) {
      try archive.checkLimits(entryCount: 3, uncompressedBytes: PackArchive.maximumUncompressedBytes + 1)
    }
  }

  @Test("an archive that unpacks larger than its headers declare is rejected after extraction")
  func lyingArchive() throws {
    let payload = Data(repeating: UInt8(ascii: "A"), count: 4 * 1024 * 1024)
    let url = root.appending(path: "bomb.zip")
    try TestZip.write(
      [
        TestZip.Entry(name: "pack.json", data: Data("{}".utf8)),
        TestZip.Entry(name: "big.bin", data: payload, deflated: true, declaredSize: 100),
      ],
      to: url
    )
    let archive = PackArchive(url: url, uncompressedBytesLimit: 1024 * 1024)
    #expect(try archive.uncompressedBytes() == 102, "the listing understates what the archive unpacks to")
    #expect(throws: PackInstallError.archiveTooLarge(payload.count + 2)) { try archive.install(into: packs) }
    #expect(!FileManager.default.fileExists(atPath: packs.path))
  }

  @Test("the folder name comes from the zip name, made safe for a path")
  func folderNames() {
    #expect(PackArchive.folderName(for: "Kaiju Pack.zip") == "Kaiju-Pack")
    #expect(PackArchive.folderName(for: "..zip") == "pack")
    #expect(PackArchive.folderName(for: "  spaced (1).ZIP") == "spaced-1")
    #expect(PackArchive.folderName(for: "怪獸.zip") == "怪獸")
  }
}
