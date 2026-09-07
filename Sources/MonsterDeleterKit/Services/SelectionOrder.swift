import Foundation

/// Finder hands the selection over in no reliable order (spike section 7); this fixes it.
public enum SelectionOrder {
  /// Finder-like ordering of paths: case-insensitive with numeric runs compared by value.
  public static func sorted(_ urls: [URL]) -> [URL] {
    urls.sorted { lhs, rhs in
      lhs.path(percentEncoded: false).localizedStandardCompare(rhs.path(percentEncoded: false)) == .orderedAscending
    }
  }
}
