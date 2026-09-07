import Foundation
import Testing

@testable import MonsterDeleterKit

/// The arrangement this Mac has: a 1x primary screen with the menu bar, a 2x screen above and to
/// the left of it, and a 1x portrait screen to its right. Both secondary screens have a negative
/// AppKit origin, so their rects reach past the top of the accessibility tree's space.
@Suite("Accessibility geometry")
struct AccessibilityGeometryTests {
  let primaryHeight: CGFloat = 1440

  func appKit(_ rect: CGRect) -> CGRect {
    AccessibilityGeometry.appKitRect(rect, primaryScreenHeight: primaryHeight)
  }

  @Test("an icon on the primary screen keeps its x and flips its y")
  func primaryScreen() {
    // The desktop icon Finder reported at 3342,38 64x64 in the accessibility tree.
    #expect(appKit(CGRect(x: 3342, y: 38, width: 64, height: 64)) == CGRect(x: 3342, y: 1338, width: 64, height: 64))
  }

  @Test("a rect on a 2x screen with a negative origin converts by points, not pixels")
  func negativeOriginRetinaScreen() {
    // Screen frame (1239, -982, 1512, 982) at 2x: its AppKit y runs from -982 to 0, which is
    // 1440 to 2422 in the accessibility tree's flipped space.
    #expect(appKit(CGRect(x: 1300, y: 1876, width: 64, height: 64)) == CGRect(x: 1300, y: -500, width: 64, height: 64))
    #expect(
      appKit(CGRect(x: 1239, y: 1440, width: 1512, height: 982)) == CGRect(x: 1239, y: -982, width: 1512, height: 982)
    )
  }

  @Test("a rect above the primary screen's top has a negative y in the accessibility tree")
  func aboveThePrimaryScreen() {
    // Screen frame (3440, -368, 1080, 1920) reaches to AppKit y 1552, past the primary's 1440.
    #expect(appKit(CGRect(x: 3500, y: -76, width: 16, height: 16)) == CGRect(x: 3500, y: 1500, width: 16, height: 16))
  }

  @Test("the conversion is its own inverse")
  func roundTrip() {
    let rect = CGRect(x: -220, y: 917.5, width: 16, height: 16)
    #expect(appKit(appKit(rect)) == rect)
  }

  @Test("the size is untouched, so a 2x backing scale changes nothing")
  func sizeIsUntouched() {
    let retina = appKit(CGRect(x: 1300, y: 1876, width: 64, height: 64))
    #expect(retina.size == CGSize(width: 64, height: 64))
  }
}
