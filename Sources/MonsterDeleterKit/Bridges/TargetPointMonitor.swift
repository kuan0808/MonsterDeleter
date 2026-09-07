import AppKit

/// AppKit bridge. A global mouse monitor that remembers the last right-click or control-click in
/// global coordinates. Mouse-only global monitors need no permission (spike section 3), and the
/// point they deliver is exact in every Finder view (spike section 4). SwiftUI has no global input.
@MainActor
public final class TargetPointMonitor {
  public private(set) var lastSample: TargetSample?
  private var monitor: Any?

  public init() {}

  public func start() {
    guard monitor == nil else { return }
    monitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
      // Global monitors deliver on the main thread; the closure type does not say so.
      MainActor.assumeIsolated {
        self?.record(event)
      }
    }
  }

  public func stop() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
  }

  private func record(_ event: NSEvent) {
    let isContextClick = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
    guard isContextClick else { return }
    // For a global monitor the event has no window, so locationInWindow is already global.
    lastSample = TargetSample(point: event.locationInWindow, takenAt: .now)
  }
}
