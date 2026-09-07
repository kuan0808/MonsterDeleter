import AppKit

/// AppKit bridge. SwiftUI has no window that is borderless, non-activating, sits at
/// `.screenSaver` level over every Space and full-screen app, and switches mouse events off and
/// on per phase. This is the spike's exact configuration; see ADR-0002 before changing any line.
@MainActor
public final class OverlayPanel: NSPanel {
  /// The screen this panel covers, in AppKit global coordinates.
  public let screenFrame: CGRect
  public let overlayView: OverlayContentView

  public init(screen: NSScreen) {
    screenFrame = screen.frame
    overlayView = OverlayContentView(frame: CGRect(origin: .zero, size: screen.frame.size))
    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = .screenSaver
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    ignoresMouseEvents = true
    contentView = overlayView
  }

  public override var canBecomeKey: Bool { true }

  /// Interactive phases receive clicks and Esc. A click-through phase may have let another app
  /// take key, so an interactive panel is always re-keyed (spike section 5).
  public func setInteractive(_ interactive: Bool) {
    ignoresMouseEvents = !interactive
    if interactive {
      makeKeyAndOrderFront(nil)
      makeFirstResponder(overlayView)
    }
  }

  /// Converts a global point to this panel's content view coordinates.
  public func localPoint(from global: CGPoint) -> CGPoint {
    CGPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
  }
}
