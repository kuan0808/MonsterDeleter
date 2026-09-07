import Testing

@testable import MonsterDeleterKit

@Suite("Easing")
struct EasingTests {
  @Test("OutQuad decelerates")
  func outQuad() {
    #expect(Easing.outQuad.value(at: 0) == 0)
    #expect(Easing.outQuad.value(at: 0.5) == 0.75)
    #expect(Easing.outQuad.value(at: 1) == 1)
  }

  @Test("InQuad accelerates")
  func inQuad() {
    #expect(Easing.inQuad.value(at: 0) == 0)
    #expect(Easing.inQuad.value(at: 0.5) == 0.25)
    #expect(Easing.inQuad.value(at: 1) == 1)
  }

  @Test("times outside 0...1 are clamped")
  func clamps() {
    #expect(Easing.inQuad.value(at: -1) == 0)
    #expect(Easing.outQuad.value(at: 2) == 1)
  }
}
