import Foundation

/// Why a dropped zip was not installed. Every case has a sentence for the settings window.
public enum PackInstallError: Error, Sendable, Hashable, LocalizedError {
  case notAZip
  /// An entry that would land outside the pack folder.
  case unsafeEntry(String)
  case noManifest
  case invalidManifest
  /// A file `pack.json` names that the zip does not contain.
  case missingFile(String)
  case extractionFailed(String)
  /// More entries than a character pack can hold.
  case tooManyEntries(Int)
  /// More unpacked bytes than a character pack can hold.
  case archiveTooLarge(Int)

  public var errorDescription: String? {
    switch self {
    case .notAZip:
      return "That is not a zip archive."
    case .unsafeEntry(let name):
      return "The archive contains an entry that would land outside the pack folder: \(name)."
    case .noManifest:
      return "The archive has no pack.json, so it is not a character pack."
    case .invalidManifest:
      return "The archive's pack.json is not a JSON object."
    case .missingFile(let name):
      return "pack.json names \(name), but the archive does not contain it."
    case .extractionFailed(let reason):
      return "The archive could not be unpacked: \(reason)"
    case .tooManyEntries(let count):
      return "The archive holds \(count) files, more than the \(PackArchive.maximumEntryCount) a pack may have."
    case .archiveTooLarge(let bytes):
      let megabyte = 1024 * 1024
      let megabytes = (bytes + megabyte - 1) / megabyte
      let limit = PackArchive.maximumUncompressedBytes / megabyte
      return "The archive unpacks to \(megabytes) MB, more than the \(limit) MB a pack may use."
    }
  }
}
