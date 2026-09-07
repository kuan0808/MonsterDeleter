import AppKit

/// AppKit bridge. The overlay's content view: accepts the first mouse click even when the panel
/// is not key, reports clicks in global coordinates, and turns Esc into a cancel. SwiftUI views
/// cannot see a click that lands outside them, nor take first responder in a non-activating panel.
@MainActor
public final class OverlayContentView: NSView {
  /// A click anywhere on the view, in AppKit global coordinates.
  public var onClick: ((CGPoint) -> Void)?
  /// Esc, through `keyDown` or the responder chain's `cancelOperation`.
  public var onCancel: (() -> Void)?

  /// Shows the crosshair cursor while aiming.
  public var usesCrosshair = false {
    didSet { window?.invalidateCursorRects(for: self) }
  }

  public override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    return nil
  }

  public override var acceptsFirstResponder: Bool { true }

  public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  public override func mouseDown(with event: NSEvent) {
    guard let window else { return }
    onClick?(window.convertPoint(toScreen: event.locationInWindow))
  }

  public override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      onCancel?()
    } else {
      super.keyDown(with: event)
    }
  }

  public override func cancelOperation(_ sender: Any?) {
    onCancel?()
  }

  public override func resetCursorRects() {
    if usesCrosshair {
      addCursorRect(bounds, cursor: .crosshair)
    }
  }
}
