import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("PackError")
struct PackErrorTests {
  @Test(
    "every load failure reads as a sentence naming what it is about",
    arguments: [
      (PackError.missingSheet(.walk), "walk"),
      (PackError.missingAudio(.bgm), "bgm"),
      (PackError.cannotRender(.point), "point"),
      (PackError.cannotSlice(.explosion), "explosion"),
      (PackError.cannotDecode("walk.png"), "walk.png"),
      (PackError.missingFile("boom.png"), "boom.png"),
      (PackError.notAPack("kaiju"), "kaiju"),
    ]
  )
  func sentences(error: PackError, subject: String) {
    let sentence = error.localizedDescription
    #expect(sentence.contains(subject), "\(String(describing: error)) does not name \(subject)")
    #expect(sentence.hasSuffix("."), "\(String(describing: error)) does not read as a sentence")
    #expect(error.errorDescription == sentence, "the settings window and the alert show the sentence")
  }
  @Test("character recovery gives a readable reason without format diagnostics")
  func characterRecovery() {
    let report = CharacterFailure.report(
      name: "Sea Monster",
      error: PackError.missingFile("walk.png"),
      wearing: "Kaiju"
    )
    #expect(report.title == "\"Sea Monster\" could not be loaded")
    #expect(
      report.message == """
        Some of this character's files are missing.

        MonsterDeleter is using Kaiju instead.

        Install it again, or pick another character in Settings.
        """
    )
    #expect(
      CharacterFailure.reason(for: PackInstallError.invalidManifest)
        == "This zip has no readable character information."
    )
    #expect(
      CharacterFailure.reason(for: PackInstallError.unsafeEntry("../outside"))
        == "This zip tries to put files outside the character's folder."
    )
  }

}
