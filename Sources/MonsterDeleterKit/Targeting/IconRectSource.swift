import Foundation

/// Where a target's icon is on screen. Finder's accessibility tree is the only real source
/// (`FinderIconReader`); this protocol is the seam that keeps the tree walk out of every test.
public protocol IconRectSource: Sendable {
  /// The icon rect of every URL it could resolve, in AppKit global coordinates. Whatever it
  /// cannot answer is simply absent: the tier below takes over per target, so there is nothing
  /// to throw and nothing to report.
  ///
  /// A source must give up when its task is cancelled. `TargetAimResolver` bounds the whole
  /// resolution by cancelling it, and a source that ignores that would delay the show.
  func iconRects(for urls: [URL]) async -> [URL: CGRect]
}
