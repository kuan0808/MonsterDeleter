import Testing

@testable import MonsterDeleterKit

@Suite("PackTexts")
struct PackTextsTests {
  let texts = PackTexts(
    bubble: "Hey, is it this one?",
    bubbleMany: "Hey, all {count} of these?",
    confirm: "Yes",
    alternate: "Yes, eat it!"
  )

  @Test("one item asks the single line")
  func single() {
    #expect(texts.bubble(count: 1) == "Hey, is it this one?")
  }

  @Test("more than one item asks the many line with the count filled in", arguments: [2, 5, 12])
  func many(count: Int) {
    #expect(texts.bubble(count: count) == "Hey, all \(count) of these?")
  }

  @Test("the placeholder pack names the count in English")
  func placeholder() {
    #expect(PackDescriptor.placeholder.texts.bubble(count: 3) == "Hey, are these 3?")
  }
}
