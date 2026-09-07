import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("AutoplayOptions")
struct AutoplayOptionsTests {
  @Test("absent variable means no autoplay")
  func absent() {
    #expect(AutoplayOptions(environment: [:]) == nil)
    #expect(AutoplayOptions(environment: ["MONSTER_AUTOPLAY": ""]) == nil)
  }

  @Test("the path alone aims at the default point with a 2 s confirm delay")
  func defaults() throws {
    let options = try #require(AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "/tmp/scratch.txt"]))
    #expect(options.targets == [URL(fileURLWithPath: "/tmp/scratch.txt")])
    #expect(options.point == nil)
    #expect(options.confirmDelay == .seconds(2))
  }

  @Test("colon-separated paths make one selection, sorted like Finder's")
  func selection() throws {
    let options = try #require(
      AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "/tmp/sel/b.txt:/tmp/sel/folder:/tmp/sel/a.txt"])
    )
    #expect(options.targets.map(\.lastPathComponent) == ["a.txt", "b.txt", "folder"])
  }

  @Test("empty path components are dropped and an all-empty list means no autoplay")
  func emptyComponents() throws {
    let options = try #require(AutoplayOptions(environment: ["MONSTER_AUTOPLAY": ":/tmp/x::"]))
    #expect(options.targets == [URL(fileURLWithPath: "/tmp/x")])
    #expect(AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "::"]) == nil)
  }

  @Test("point and delay are parsed")
  func explicitValues() throws {
    let options = try #require(
      AutoplayOptions(environment: [
        "MONSTER_AUTOPLAY": "/tmp/scratch.txt",
        "MONSTER_AUTOPLAY_POINT": "1584, 211.5",
        "MONSTER_AUTOPLAY_CONFIRM_DELAY": "0.25",
      ])
    )
    #expect(options.point == CGPoint(x: 1584, y: 211.5))
    #expect(options.confirmDelay == .milliseconds(250))
  }

  @Test(
    "a malformed point falls back to the default",
    arguments: ["12", "10,abc,20", "x,1,2,y", "1,", "nan,nan", ""]
  )
  func malformedPoint(text: String) throws {
    let options = try #require(
      AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "/tmp/x", "MONSTER_AUTOPLAY_POINT": text])
    )
    #expect(options.point == nil)
  }

  @Test(
    "a non-finite or negative confirm delay falls back to 2 s",
    arguments: ["nan", "inf", "-1", "soon"]
  )
  func malformedConfirmDelay(text: String) throws {
    let options = try #require(
      AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "/tmp/x", "MONSTER_AUTOPLAY_CONFIRM_DELAY": text])
    )
    #expect(options.confirmDelay == .seconds(2))
  }

  @Test("the answer, snapshot folder and reference folder default to the button and no captures")
  func selfTestDefaults() throws {
    let options = try #require(AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "/tmp/x"]))
    #expect(options.answer == .confirm)
    #expect(options.snapshotDirectory == nil)
    #expect(options.referenceDirectory == nil)
    #expect(options.packID == nil, "without the variable the self-test keeps its forced placeholder")
  }

  @Test("MONSTER_AUTOPLAY_PACK carries the pack id the show wears")
  func packID() throws {
    let options = try #require(
      AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "/tmp/x", "MONSTER_AUTOPLAY_PACK": " builtIn/kaiju "])
    )
    #expect(options.packID == "builtIn/kaiju")
  }

  @Test("an empty MONSTER_AUTOPLAY_PACK is no choice at all", arguments: ["", "   "])
  func emptyPackID(text: String) throws {
    let options = try #require(
      AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "/tmp/x", "MONSTER_AUTOPLAY_PACK": text])
    )
    #expect(options.packID == nil)
  }

  /// An id no pack answers to is carried through as written; `AppDelegate` ends the run on it
  /// rather than falling back, so a capture can never be of the wrong pack.
  @Test("an unknown pack id is carried through rather than dropped")
  func unknownPackID() throws {
    let options = try #require(
      AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "/tmp/x", "MONSTER_AUTOPLAY_PACK": "user/nope"])
    )
    #expect(options.packID == "user/nope")
  }

  @Test("MONSTER_AUTOPLAY_ANSWER=esc presses Esc instead of the button; anything else is the button")
  func answer() throws {
    let esc = try #require(
      AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "/tmp/x", "MONSTER_AUTOPLAY_ANSWER": "esc"])
    )
    #expect(esc.answer == .escape)
    let typo = try #require(
      AutoplayOptions(environment: ["MONSTER_AUTOPLAY": "/tmp/x", "MONSTER_AUTOPLAY_ANSWER": "no"])
    )
    #expect(typo.answer == .confirm)
  }

  @Test("the snapshot and reference folders are file URLs; an empty value means none")
  func folders() throws {
    let options = try #require(
      AutoplayOptions(environment: [
        "MONSTER_AUTOPLAY": "/tmp/x",
        "MONSTER_AUTOPLAY_SNAPSHOTS": "/tmp/out",
        "MONSTER_AUTOPLAY_REFERENCE": "",
      ])
    )
    #expect(options.snapshotDirectory == URL(fileURLWithPath: "/tmp/out", isDirectory: true))
    #expect(options.referenceDirectory == nil)
  }

  @Test(
    "the show count defaults to one and never drops below it",
    arguments: [(nil, 1), ("10", 10), ("0", 1), ("-3", 1), ("many", 1)]
  )
  func shows(text: String?, expected: Int) throws {
    var environment = ["MONSTER_AUTOPLAY": "/tmp/x"]
    environment["MONSTER_AUTOPLAY_SHOWS"] = text
    let options = try #require(AutoplayOptions(environment: environment))
    #expect(options.shows == expected)
  }
}
