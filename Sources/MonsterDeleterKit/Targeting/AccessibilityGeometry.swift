import Foundation

/// The one conversion between the accessibility API's coordinates and the show's.
///
/// The accessibility tree reports positions in a flipped global space: the origin is the
/// top-left corner of the screen that carries the menu bar and y grows downwards. Everything
/// else in the app is in AppKit global coordinates, whose origin is that same screen's
/// bottom-left corner with y growing upwards. Both are in points, so a screen's backing scale
/// never enters the arithmetic (Phase 1 spike section 4), and a screen with a negative origin
/// simply lands outside the primary screen's own span.
public enum AccessibilityGeometry {
  /// `rect` in AppKit global coordinates. `primaryScreenHeight` is `NSScreen.screens[0]`'s
  /// height, the one screen both spaces are anchored to.
  public static func appKitRect(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
    CGRect(
      x: rect.minX,
      y: primaryScreenHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }
}
