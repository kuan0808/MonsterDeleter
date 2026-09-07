import Foundation
import os

/// What became of one file dropped on the settings window: the sentence to show and whether it is
/// a rejection. A drop or a file import can carry several files, and each one gets its own line.
public struct InstallOutcome: Sendable, Hashable {
  public let message: String
  public let isFailure: Bool

  public init(message: String, isFailure: Bool) {
    self.message = message
    self.isFailure = isFailure
  }

  /// One outcome per file, in drop order. A file that is not a zip is a rejection without
  /// reaching `install`. The current-pack sentence is settled once the whole batch is in, since
  /// each install of the batch takes the chosen pack from the one before it: only the pack that
  /// is current at the end carries it.
  @MainActor
  public static func outcomes(
    for urls: [URL],
    install: (URL) async throws -> PackInstallation,
    isCurrent: (PackEntry.ID) -> Bool,
    wearing: () async -> String?
  ) async -> [InstallOutcome] {
    var outcomes: [InstallOutcome] = []
    var installed: [(line: Int, entry: PackEntry)] = []
    var failed: [Int] = []
    for url in urls {
      let file = url.lastPathComponent
      guard url.pathExtension.lowercased() == "zip" else {
        outcomes.append(InstallOutcome(message: "\(file) is not a zip archive.", isFailure: true))
        continue
      }
      do {
        let installation = try await install(url)
        installed.append((outcomes.count, installation.entry))
        outcomes.append(InstallOutcome(message: "Installed \(installation.entry.name).", isFailure: false))
      } catch {
        let logger = Logger(subsystem: "io.github.kuan0808.MonsterDeleter", category: "pack")
        logger.error("Cannot install \(file, privacy: .public): \(String(describing: error), privacy: .public)")
        failed.append(outcomes.count)
        outcomes.append(
          InstallOutcome(
            message: "\(file): \(CharacterFailure.reason(for: error))",
            isFailure: true
          )
        )
      }
    }
    if !failed.isEmpty {
      let replacement = CharacterFailure.replacement(wearing: await wearing())
      for line in failed {
        outcomes[line] = InstallOutcome(
          message: "\(outcomes[line].message) \(replacement) Get a new copy and try Choose Zip in Settings.",
          isFailure: true
        )
      }
    }
    for (line, entry) in installed where isCurrent(entry.id) {
      outcomes[line] = InstallOutcome(
        message: "Installed \(entry.name). It is now your character.",
        isFailure: false
      )
    }
    return outcomes
  }
}
