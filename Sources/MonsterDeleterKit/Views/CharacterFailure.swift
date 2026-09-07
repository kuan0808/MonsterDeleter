import Foundation

public enum CharacterFailure {
  public static func reason(for error: any Error) -> String {
    if let error = error as? PackError {
      return switch error {
      case .missingSheet, .cannotRender, .cannotSlice, .cannotDecode:
        "This character's artwork could not be read."
      case .missingAudio:
        "This character's sound could not be read."
      case .missingFile:
        "Some of this character's files are missing."
      case .notAPack:
        "This character's information is missing or unreadable."
      }
    }
    if let error = error as? PackInstallError {
      return switch error {
      case .notAZip:
        "Choose a character .zip file."
      case .unsafeEntry:
        "This zip tries to put files outside the character's folder."
      case .noManifest, .invalidManifest:
        "This zip has no readable character information."
      case .missingFile:
        "Some of this character's files are missing."
      case .extractionFailed:
        "This zip could not be opened."
      case .tooManyEntries, .archiveTooLarge:
        "This character is too large to install."
      }
    }
    if let error = error as? CocoaError, error.code == .fileWriteOutOfSpace {
      return "There is not enough space on your Mac."
    }
    return "This character's files could not be read or saved."
  }

  public static func replacement(wearing: String?) -> String {
    wearing.map { "MonsterDeleter is using \($0) instead." } ?? "No other character could be loaded either."
  }

  public static func report(name: String, error: any Error, wearing: String?) -> LoadFailureQueue.Report {
    LoadFailureQueue.Report(
      title: "\"\(name)\" could not be loaded",
      message: [
        reason(for: error),
        replacement(wearing: wearing),
        "Install it again, or pick another character in Settings.",
      ].joined(separator: "\n\n")
    )
  }
}
