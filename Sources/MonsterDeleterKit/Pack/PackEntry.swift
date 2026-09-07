import Foundation

/// One pack the library knows about, before it is loaded. Every entry is a folder on disk: the
/// generated placeholder is not one, because it is not a pack a user can choose
/// (`docs/adr/0007-no-placeholder-fallback.md`).
public struct PackEntry: Identifiable, Sendable, Hashable {
  public enum Origin: String, Sendable {
    /// Ships inside the app bundle, under `Contents/Resources/packs/`.
    case builtIn
    /// Installed under Application Support by the user.
    case user
  }

  public let origin: Origin
  /// The pack's folder name, which is also the second half of its id.
  public let folderName: String
  public let name: String
  public let folder: URL

  public init(origin: Origin, folderName: String, name: String, folder: URL) {
    self.origin = origin
    self.folderName = folderName
    self.name = name
    self.folder = folder
  }

  /// `builtIn/kaiju`, `user/Sea-Monster`: stable across launches and safe in `UserDefaults`.
  public var id: String { "\(origin.rawValue)/\(folderName)" }

  /// The id `origin` and `folderName` make, without a loaded folder to hand.
  public static func id(origin: Origin, folderName: String) -> ID { "\(origin.rawValue)/\(folderName)" }
}
