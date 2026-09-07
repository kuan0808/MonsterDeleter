import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import MonsterDeleterKit

/// The gallery shows the characters themselves, so a folder that changed under the same id - what
/// installing a zip over a pack does - has to be read again rather than served from the first look.
@Suite("Pack previews")
@MainActor
struct PackPreviewsTests {
  let root: URL
  let packs: URL
  let defaults: UserDefaults

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "PackPreviewsTests-\(UUID().uuidString)")
    packs = root.appending(path: "packs")
    try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
    defaults = try #require(UserDefaults(suiteName: "PackPreviewsTests-\(UUID().uuidString)"))
  }

  private func makeLibrary() -> PackLibrary {
    PackLibrary(
      userPacksDirectory: packs,
      cacheDirectory: root.appending(path: "cache"),
      defaults: defaults
    )
  }

  /// A pack whose point sheet is its own file, so its tile has a colour the test can read back.
  private func addPack(_ folder: String, name: String) throws {
    let directory = packs.appending(path: folder)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manifest = #"{"name": "\#(name)", "sheets": {"point": {"file": "point.png"}}}"#
    try Data(manifest.utf8).write(to: directory.appending(path: "pack.json"))
  }

  /// The slicing cache keys on the sheet's modification date, so each write says when it happened.
  private func writeSheet(_ folder: String, gray: CGFloat, at seconds: TimeInterval) throws {
    let file = packs.appending(path: folder).appending(path: "point.png")
    try TestImages.writeSheet(to: file, gray: gray)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: seconds)],
      ofItemAtPath: file.path
    )
  }

  private func red(_ previews: PackPreviews, _ id: PackEntry.ID) throws -> UInt8 {
    let frame = try #require(previews.frames[id])
    return try #require(TestImages.firstRed(of: frame))
  }

  @Test("a pack installed over an old one shows its new artwork")
  func reinstalledArtwork() async throws {
    try addPack("alpha", name: "Alpha")
    try writeSheet("alpha", gray: 0.2, at: 1_700_000_000)
    try addPack("zebra", name: "Zebra")
    try writeSheet("zebra", gray: 0.2, at: 1_700_000_000)
    let library = makeLibrary()
    let previews = PackPreviews()
    await previews.load(library.entries, from: library)
    #expect(try red(previews, "user/zebra") == 51)
    try writeSheet("zebra", gray: 1.0, at: 1_700_000_001)
    await previews.load(library.entries, from: library, reloading: ["user/zebra"])
    #expect(try red(previews, "user/zebra") == 255)
  }

  /// Choosing a character is instant but loading one is not, so between the two the library's
  /// chosen id and the pack it is still wearing name different characters. A tile taken from the
  /// worn pack in that window is the wrong artwork under the right name.
  @Test("a character chosen but not loaded yet shows its own artwork, not the one still worn")
  func tileOfAChosenPackThatIsStillLoading() async throws {
    try addPack("alpha", name: "Alpha")
    try writeSheet("alpha", gray: 0.2, at: 1_700_000_000)
    try addPack("zebra", name: "Zebra")
    try writeSheet("zebra", gray: 1.0, at: 1_700_000_000)
    defaults.set("user/zebra", forKey: PackLibrary.selectionKey)
    let library = makeLibrary()
    _ = await library.currentPack()
    library.select("user/alpha")

    let previews = PackPreviews()
    await previews.load(library.entries, from: library)
    #expect(try red(previews, "user/alpha") == 51, "Alpha's own artwork, not the Zebra still worn")
    #expect(try red(previews, "user/zebra") == 255)
  }

  @Test("a failed replacement preserves the gallery tile until new artwork loads")
  func failedReplacementKeepsGalleryIdentity() async throws {
    _ = NSApplication.shared
    try addPack("sea", name: "Sea")
    try writeSheet("sea", gray: 0.2, at: 1_700_000_000)
    let library = makeLibrary()
    _ = await library.currentPack()
    let previews = PackPreviews()
    await previews.load(library.entries, from: library)
    let settings = SettingsView(
      library: library,
      iconAiming: IconAiming(defaults: defaults, prompt: { false }, trusted: { false }, openURL: { _ in }),
      sound: ShowSound(defaults: defaults)
    )
    func tile() throws -> Data {
      let entry = try #require(library.entries.first { $0.id == "user/sea" })
      let renderer = ImageRenderer(content: settings.characterButton(entry).environment(\.colorScheme, .light))
      let image = try #require(renderer.cgImage)
      return try #require(image.dataProvider?.data as Data?)
    }
    let original = try tile()
    let zip = root.appending(path: "sea.zip")
    let manifest = Data(#"{"name":"New Sea","sheets":{"point":{"file":"point.png"}}}"#.utf8)
    try TestZip.write(
      [
        ("pack.json", manifest), ("point.png", Data("unreadable artwork".utf8)),
      ],
      to: zip
    )
    await #expect(throws: PackError.cannotDecode("point.png")) { try await library.install(zipAt: zip) }
    await previews.load(library.entries, from: library)
    #expect(library.entries.first?.name == "New Sea")
    #expect(try tile() == original, "the visible selected tile keeps the retained character's name")
    #expect(try red(previews, "user/sea") == 51)

    let sheet = root.appending(path: "replacement.png")
    try TestImages.writeSheet(to: sheet, gray: 1)
    try TestZip.write([("pack.json", manifest), ("point.png", try Data(contentsOf: sheet))], to: zip)
    _ = try await library.install(zipAt: zip)
    await previews.load(library.entries, from: library, reloading: ["user/sea"])
    #expect(try tile() != original, "a successful replacement updates the rendered name")
    #expect(try red(previews, "user/sea") == 255)
  }

  @Test("a character that could not be read at all gets its tile once it can be")
  func fixedPackGetsATile() async throws {
    try addPack("alpha", name: "Alpha")
    try writeSheet("alpha", gray: 0.2, at: 1_700_000_000)
    try addPack("zebra", name: "Zebra")
    let library = makeLibrary()
    let previews = PackPreviews()
    await previews.load(library.entries, from: library)
    #expect(previews.frames["user/zebra"] == nil, "its point sheet is missing, so there is nothing to show")
    try writeSheet("zebra", gray: 1.0, at: 1_700_000_001)
    await previews.load(library.entries, from: library, reloading: ["user/zebra"])
    #expect(try red(previews, "user/zebra") == 255)
  }
}
