import AppKit
import UserNotifications
import os

/// UserNotifications bridge. Tells the user which items stayed put after the show, without a
/// modal dialog over Finder: a notification when the user allows them, else the alert. SwiftUI
/// has no notification API and the menu bar app has no window to hang a sheet on. Keep one
/// instance alive for the app's lifetime; the notification centre only holds its delegate weakly.
@MainActor
public final class TrashFailureNotice: NSObject {
  private let logger = Logger(subsystem: "io.github.kuan0808.MonsterDeleter", category: "trash")

  private let activation: AppActivation

  public init(activation: AppActivation = AppActivation()) {
    self.activation = activation
    super.init()
  }

  /// "The monster could not trash “x”" for one failure, "… 2 of 3 items" for more.
  public nonisolated static func title(for outcome: TrashOutcome) -> String {
    if outcome.failures.count == 1, let failure = outcome.failures.first {
      return "The monster could not trash “\(failure.url.lastPathComponent)”"
    }
    let total = outcome.trashed.count + outcome.failures.count
    return "The monster could not trash \(outcome.failures.count) of \(total) items"
  }

  /// The most "name: reason" lines the notice lists before the "and N more" line. A whole
  /// read-only selection can fail at once, and the alert fallback grows its window to fit.
  public nonisolated static let maxListedFailures = 5

  /// The reason, or one "name: reason" line per failure, the first `maxListedFailures` of them
  /// followed by "and N more".
  public nonisolated static func body(for outcome: TrashOutcome) -> String {
    if outcome.failures.count == 1, let failure = outcome.failures.first {
      return failure.message
    }
    var lines = outcome.failures.prefix(maxListedFailures).map { "\($0.url.lastPathComponent): \($0.message)" }
    let hidden = outcome.failures.count - lines.count
    if hidden > 0 {
      lines.append("and \(hidden) more")
    }
    return lines.joined(separator: "\n")
  }

  /// Presents the failures of `outcome`, if any, and returns once the notice is delivered.
  public func present(_ outcome: TrashOutcome) async {
    guard !outcome.failures.isEmpty else { return }
    let title = Self.title(for: outcome)
    let body = Self.body(for: outcome)
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    do {
      guard try await center.requestAuthorization(options: [.alert]) else {
        logger.notice("Notifications not allowed; falling back to an alert")
        presentAlert(title: title, body: body)
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    } catch {
      logger.error("Cannot notify: \(error.localizedDescription, privacy: .public)")
      presentAlert(title: title, body: body)
    }
  }

  private func presentAlert(title: String, body: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = body
    alert.alertStyle = .warning
    activation.activate()
    alert.runModal()
  }
}

extension TrashFailureNotice: UNUserNotificationCenterDelegate {
  /// Shows the banner even while the app is active, which it may still be right after the ask.
  public nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }
}
