import Testing

@testable import MonsterDeleterKit

/// The offer of icon aiming follows the experience: it belongs to a show whose explosions really
/// landed in a ring, not to one the user cancelled or one that never ran.
@Suite("Unaimed fan")
struct UnaimedFanTests {
  @Test("a finished show of several whose icons could not be read is the ring")
  func ring() {
    let fan = UnaimedFan(targetCount: 2, resolvedIcons: 0)
    #expect(fan.landedInARing(endingIn: .done))
  }

  @Test("a cancelled show explains nothing, however it was aimed")
  func cancelled() {
    let fan = UnaimedFan(targetCount: 2, resolvedIcons: 0)
    #expect(!fan.landedInARing(endingIn: .cancelled))
  }

  @Test("a show whose icons were read explodes on the files, so there is no ring to explain")
  func aimed() {
    #expect(!UnaimedFan(targetCount: 2, resolvedIcons: 2).landedInARing(endingIn: .done))
    #expect(!UnaimedFan(targetCount: 3, resolvedIcons: 1).landedInARing(endingIn: .done))
  }

  @Test("a single item has no fan: its explosion stays on the point either way")
  func singleItem() {
    #expect(!UnaimedFan(targetCount: 1, resolvedIcons: 0).landedInARing(endingIn: .done))
  }
}
