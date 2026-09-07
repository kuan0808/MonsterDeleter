import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("PackManifest")
struct PackManifestTests {
  @Test("an empty manifest is the built-in defaults with no warnings")
  func emptyManifest() throws {
    let manifest = try PackManifest(json: Data("{}".utf8))
    #expect(manifest.descriptor == .defaults)
    #expect(manifest.warnings.isEmpty)
    #expect(manifest.declaredSheets.isEmpty)
    #expect(manifest.declaredAudio.isEmpty)
    let defaults = PackDescriptor.defaults
    #expect(defaults.framesPerSecond == 8)
    #expect(defaults.characterHeight == 250)
    #expect(defaults.pointFrames == 11...14)
    #expect(defaults.kickImpactFrame == 5)
    #expect(defaults.walkSeconds == 4.5)
    #expect(defaults.flySeconds == 2.0)
    #expect(defaults.sheets[.walk] == SheetDescriptor(file: "walk.png", columns: 5, rows: 3))
    #expect(defaults.audio[.bgm] == AudioDescriptor(file: "bgm.wav", volume: 0.5, loops: true))
    #expect(defaults.tint == nil)
  }

  @Test("declared fields override the defaults and unknown fields are ignored")
  func declaredFields() throws {
    let json = """
      {
        "name": "Kaiju",
        "description": "A big one.",
        "framesPerSecond": 12,
        "characterHeight": 300,
        "pointFrames": [10, 13],
        "kickImpactFrame": 7,
        "walkSeconds": 3,
        "flySeconds": 1.5,
        "sheets": { "walk": { "file": "kaiju-walk.png" }, "explosion": { "file": "boom.png", "columns": 4, "rows": 4 } },
        "audio": { "voice": { "file": "roar.mp3", "volume": 0.8 } },
        "texts": { "bubble": "This one?" },
        "tint": "#BBD7FF",
        "author": "someone",
        "version": 3
      }
      """
    let manifest = try PackManifest(json: Data(json.utf8))
    let pack = manifest.descriptor
    #expect(manifest.warnings.isEmpty)
    #expect(pack.name == "Kaiju")
    #expect(pack.description == "A big one.")
    #expect(pack.framesPerSecond == 12)
    #expect(pack.characterHeight == 300)
    #expect(pack.pointFrames == 10...13)
    #expect(pack.kickImpactFrame == 7)
    #expect(pack.walkSeconds == 3)
    #expect(pack.flySeconds == 1.5)
    #expect(pack.sheets[.walk] == SheetDescriptor(file: "kaiju-walk.png", columns: 5, rows: 3))
    #expect(pack.sheets[.explosion] == SheetDescriptor(file: "boom.png", columns: 4, rows: 4))
    #expect(pack.sheets[.kick] == PackDescriptor.defaults.sheets[.kick])
    #expect(pack.audio[.voice] == AudioDescriptor(file: "roar.mp3", volume: 0.8, loops: false))
    #expect(pack.audio[.bgm] == PackDescriptor.defaults.audio[.bgm])
    #expect(pack.texts.bubble == "This one?")
    #expect(pack.texts.confirm == PackDescriptor.defaults.texts.confirm)
    #expect(pack.tint == PackTint(red: 0xBB, green: 0xD7, blue: 0xFF))
    #expect(manifest.declaredSheets == [.walk, .explosion])
    #expect(manifest.declaredAudio == [.voice])
  }

  @Test("malformed values fall back to the defaults, each with a warning naming the field")
  func malformedValues() throws {
    let json = """
      {
        "name": 7,
        "framesPerSecond": "fast",
        "characterHeight": -10,
        "pointFrames": [14, 11],
        "kickImpactFrame": 99,
        "walkSeconds": "long",
        "sheets": { "walk": { "file": 3 }, "kick": { "file": "kick.png", "columns": 0 }, "dance": { "file": "d.png" } },
        "audio": { "bgm": "bgm.mp3", "voice": { "file": "v.mp3", "volume": 4 } },
        "texts": { "bubble": 5, "confirm": "OK" },
        "tint": "blue"
      }
      """
    let manifest = try PackManifest(json: Data(json.utf8))
    let pack = manifest.descriptor
    let defaults = PackDescriptor.defaults
    #expect(pack.name == defaults.name)
    #expect(pack.framesPerSecond == defaults.framesPerSecond)
    #expect(pack.characterHeight == defaults.characterHeight)
    #expect(pack.pointFrames == defaults.pointFrames)
    #expect(pack.kickImpactFrame == defaults.kickImpactFrame)
    #expect(pack.walkSeconds == defaults.walkSeconds)
    #expect(pack.sheets[.walk] == defaults.sheets[.walk])
    #expect(pack.sheets[.kick] == SheetDescriptor(file: "kick.png", columns: 5, rows: 3))
    #expect(pack.audio[.bgm] == defaults.audio[.bgm])
    #expect(pack.audio[.voice] == AudioDescriptor(file: "v.mp3", volume: 1.0, loops: false))
    #expect(pack.texts.bubble == defaults.texts.bubble)
    #expect(pack.texts.confirm == "OK")
    #expect(pack.tint == nil)
    #expect(manifest.declaredSheets == [.kick])
    #expect(manifest.declaredAudio == [.voice])
    for field in [
      "name", "framesPerSecond", "characterHeight", "pointFrames", "kickImpactFrame", "walkSeconds",
      "sheets.walk.file", "sheets.kick.columns", "sheets.dance", "audio.bgm", "audio.voice.volume", "texts.bubble",
      "tint",
    ] {
      #expect(manifest.warnings.contains { $0.hasPrefix(field) }, "no warning for \(field): \(manifest.warnings)")
    }
    #expect(manifest.warnings.count == 13)
  }

  @Test("the fan radius and the many-target bubble decode, and fall back with a warning")
  func fanRadiusAndBubbleMany() throws {
    let good = try PackManifest(
      json: Data(#"{ "explosionFanRadius": 120, "texts": { "bubbleMany": "All {count} of them?" } }"#.utf8)
    )
    #expect(good.warnings.isEmpty)
    #expect(good.descriptor.explosionFanRadius == 120)
    #expect(good.descriptor.texts.bubble(count: 3) == "All 3 of them?")

    let bad = try PackManifest(
      json: Data(#"{ "explosionFanRadius": -5, "texts": { "bubbleMany": 7 } }"#.utf8)
    )
    let defaults = PackDescriptor.defaults
    #expect(bad.descriptor.explosionFanRadius == defaults.explosionFanRadius)
    #expect(bad.descriptor.texts.bubbleMany == defaults.texts.bubbleMany)
    #expect(bad.warnings.contains { $0.hasPrefix("explosionFanRadius") })
    #expect(bad.warnings.contains { $0.hasPrefix("texts.bubbleMany") })
  }

  @Test("an entry without a file name keeps its grid or volume and uses the default file name")
  func entryWithoutFileName() throws {
    let json = """
      { "sheets": { "walk": { "columns": 6, "rows": 2 } }, "audio": { "voice": { "volume": 0.25 } } }
      """
    let manifest = try PackManifest(json: Data(json.utf8))
    #expect(manifest.warnings.isEmpty)
    #expect(manifest.descriptor.sheets[.walk] == SheetDescriptor(file: "walk.png", columns: 6, rows: 2))
    #expect(manifest.descriptor.audio[.voice] == AudioDescriptor(file: "voice.wav", volume: 0.25, loops: false))
    #expect(manifest.declaredSheets.isEmpty, "a defaulted file name is not a declared file")
    #expect(manifest.declaredAudio.isEmpty)
  }

  @Test("the manifest says whether the frame indices came from the JSON")
  func explicitFrameIndices() throws {
    let absent = try PackManifest(json: Data("{}".utf8))
    #expect(!absent.explicitPointFrames)
    #expect(!absent.explicitKickImpactFrame)
    let given = try PackManifest(json: Data(#"{"pointFrames": [1, 2], "kickImpactFrame": 3}"#.utf8))
    #expect(given.explicitPointFrames)
    #expect(given.explicitKickImpactFrame)
    let rejected = try PackManifest(json: Data(#"{"pointFrames": [1, 99], "kickImpactFrame": 99}"#.utf8))
    #expect(!rejected.explicitPointFrames, "an out-of-range range is not the author's value")
    #expect(!rejected.explicitKickImpactFrame)
  }

  @Test("a grid side out of bounds falls back to the default grid instead of overflowing the frame count")
  func hugeGrid() throws {
    let json = #"{ "sheets": { "point": { "columns": 3037000500, "rows": 3037000500 }, "kick": { "rows": 4097 } } }"#
    let manifest = try PackManifest(json: Data(json.utf8))
    let defaults = PackDescriptor.defaults
    #expect(manifest.descriptor.sheets[.point] == defaults.sheets[.point])
    #expect(manifest.descriptor.sheets[.kick] == defaults.sheets[.kick])
    #expect(manifest.descriptor.sheets[.point]?.frameCount == SheetDescriptor.standardFrameCount)
    #expect(manifest.descriptor.pointFrames == defaults.pointFrames)
    #expect(manifest.descriptor.kickImpactFrame == defaults.kickImpactFrame)
    for field in ["sheets.point.columns", "sheets.point.rows", "sheets.kick.rows"] {
      #expect(manifest.warnings.contains { $0.hasPrefix(field) }, "no warning for \(field): \(manifest.warnings)")
    }
  }

  @Test("a tint must be six hex digits", arguments: ["+12345", "#-12345", "#12345", "1234567", "12345g", "blue"])
  func invalidTint(text: String) throws {
    #expect(PackTint(hex: text) == nil)
    let manifest = try PackManifest(json: Data(#"{"tint": "\#(text)"}"#.utf8))
    #expect(manifest.descriptor.tint == nil)
    #expect(manifest.warnings.contains { $0.hasPrefix("tint") })
  }

  @Test("point frames and the impact frame must fit the kick sheet's grid")
  func frameIndicesAgainstGrid() throws {
    let json = """
      { "sheets": { "kick": { "file": "k.png", "columns": 3, "rows": 2 }, "point": { "file": "p.png", "columns": 2, "rows": 2 } },
        "pointFrames": [2, 5], "kickImpactFrame": 5 }
      """
    let manifest = try PackManifest(json: Data(json.utf8))
    #expect(manifest.descriptor.pointFrames == 0...3, "a point range past the point sheet's 4 frames uses the sheet")
    #expect(manifest.descriptor.kickImpactFrame == 5, "frame 5 is the last of the kick sheet's 6")
    #expect(manifest.warnings.count == 1)
  }

  @Test("something that is not a JSON object is not a manifest")
  func notAnObject() {
    #expect(throws: (any Error).self) { try PackManifest(json: Data("[1, 2]".utf8)) }
    #expect(throws: (any Error).self) { try PackManifest(json: Data("{ not json".utf8)) }
  }

  @Test("the placeholder descriptor round-trips through pack.json")
  func placeholderRoundTrip() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(PackDescriptor.placeholder)
    let manifest = try PackManifest(json: data)
    #expect(manifest.descriptor == .placeholder)
    #expect(manifest.warnings.isEmpty)
    #expect(manifest.declaredSheets == Set(SheetRole.allCases))
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"walk\":{\"columns\":5,\"file\":\"walk.png\",\"rows\":3}"))
    #expect(json.contains("\"pointFrames\":[11,14]"))
    #expect(!json.contains("tint"), "an absent tint is not written")
  }

  @Test("a tint encodes as a hex string")
  func tintEncoding() throws {
    var pack = PackDescriptor.defaults
    pack.tint = PackTint(red: 0xBB, green: 0xD7, blue: 0xFF)
    let data = try JSONEncoder().encode(pack)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"tint\":\"#BBD7FF\""))
    #expect(try PackManifest(json: data).descriptor.tint == pack.tint)
  }
}
