import Foundation

/// What happened to each requested item after the kick.
public struct TrashOutcome: Sendable, Hashable {
  public struct Failure: Sendable, Hashable {
    public var url: URL
    public var message: String
  }

  /// Source URL to its new location in the Trash.
  public var trashed: [URL: URL]
  public var failures: [Failure]

  public init(trashed: [URL: URL], failures: [Failure]) {
    self.trashed = trashed
    self.failures = failures
  }

  /// Builds the outcome from `NSWorkspace.recycle`'s completion: per-item errors live in
  /// `NSMultipleUnderlyingErrorsKey`, each carrying its `NSURLErrorKey` (spike section 6). Every
  /// requested item ends up either trashed or in `failures`; an item the error does not name
  /// gets the batch message.
  public init(requested: [URL], trashed: [URL: URL], error: (any Error)?) {
    self.trashed = trashed
    guard let error else {
      failures = []
      return
    }
    let nsError = error as NSError
    let underlying = nsError.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] ?? []
    var failures: [Failure] = []
    for item in underlying {
      if let url = item.userInfo[NSURLErrorKey] as? URL {
        failures.append(Failure(url: url, message: item.localizedDescription))
      }
    }
    let named = Set(failures.map(\.url))
    for url in requested where trashed[url] == nil && !named.contains(url) {
      failures.append(Failure(url: url, message: nsError.localizedDescription))
    }
    self.failures = failures
  }
}
