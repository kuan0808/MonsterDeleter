import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("Show sound")
@MainActor
struct ShowSoundTests {
  let defaults: UserDefaults

  init() throws {
    defaults = try #require(UserDefaults(suiteName: "ShowSoundTests-\(UUID().uuidString)"))
  }

  @Test("an install that has never touched the switch gets sound")
  func onByDefault() {
    #expect(ShowSound(defaults: defaults).isEnabled)
  }

  @Test("muting survives a relaunch")
  func mutePersists() {
    ShowSound(defaults: defaults).setEnabled(false)
    #expect(!ShowSound(defaults: defaults).isEnabled)
  }
}
