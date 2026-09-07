/// Pack load failures waiting for a quiet moment. The show's overlay panel sits above a modal
/// alert, so a failure raised while a show is on screen is held until the show has finished.
public struct LoadFailureQueue: Sendable, Hashable {
  /// One failure as the user should read it.
  public struct Report: Sendable, Hashable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
      self.title = title
      self.message = message
    }
  }

  private var pending: [Report] = []

  public init() {}

  /// Takes a failure and answers with what to show now: nothing while a show is running.
  public mutating func enqueue(_ report: Report, showIsRunning: Bool) -> [Report] {
    pending.append(report)
    return showIsRunning ? [] : drain()
  }

  /// The held failures, once.
  public mutating func drain() -> [Report] {
    defer { pending.removeAll() }
    return pending
  }
}
