import Foundation

/// Failures while loading a pack. Every case has a sentence, since a load failure reaches the
/// settings window and the alert.
public enum PackError: Error, Sendable, Hashable, LocalizedError {
  case missingSheet(SheetRole)
  case missingAudio(AudioRole)
  case cannotRender(SheetRole)
  case cannotSlice(SheetRole)
  /// A file `pack.json` names is absent or not an image.
  case cannotDecode(String)
  /// A file `pack.json` names is absent.
  case missingFile(String)
  /// The folder has no readable `pack.json`.
  case notAPack(String)

  public var errorDescription: String? {
    switch self {
    case .missingSheet(let role):
      return "The pack has no \(role.rawValue) sheet."
    case .missingAudio(let role):
      return "The pack has no \(role.rawValue) sound."
    case .cannotRender(let role):
      return "The \(role.rawValue) sheet could not be drawn."
    case .cannotSlice(let role):
      return "The \(role.rawValue) sheet could not be cut into frames."
    case .cannotDecode(let name):
      return "\(name) is not an image the app can read."
    case .missingFile(let name):
      return "pack.json names \(name), but the pack folder does not contain it."
    case .notAPack(let name):
      return "\(name) has no readable pack.json, so it is not a character pack."
    }
  }
}
