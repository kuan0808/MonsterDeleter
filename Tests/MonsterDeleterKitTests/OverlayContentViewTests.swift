import AppKit
import Testing

@testable import MonsterDeleterKit

@Suite("OverlayContentView")
@MainActor
struct OverlayContentViewTests {
  let view = OverlayContentView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

  func key(code: UInt16, characters: String) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: code
    )
  }

  @Test("Esc is a cancel, through keyDown and through cancelOperation")
  func escapeCancels() throws {
    var cancels = 0
    view.onCancel = { cancels += 1 }
    view.keyDown(with: try #require(key(code: 53, characters: "\u{1B}")))
    #expect(cancels == 1)
    view.cancelOperation(nil)
    #expect(cancels == 2)
  }

  @Test("other keys are not a cancel", arguments: [(UInt16(36), "\r"), (49, " "), (0, "a")])
  func otherKeysIgnored(code: UInt16, characters: String) throws {
    var cancels = 0
    view.onCancel = { cancels += 1 }
    view.keyDown(with: try #require(key(code: code, characters: characters)))
    #expect(cancels == 0)
  }

  @Test("the view takes first responder and the first click, as the ask needs")
  func responder() {
    #expect(view.acceptsFirstResponder)
    #expect(view.acceptsFirstMouse(for: nil))
  }
}
