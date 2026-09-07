import CoreGraphics
import Foundation

/// A pack read from a folder: `pack.json` plus the sheets and sounds it names. A file the manifest
/// declares must exist; a role it leaves out is read from the default-named file when the folder
/// has one and from the built-in placeholder otherwise, so a `pack.json` alone is a valid re-skin.
/// Sheets go through the slicing cache.
public struct FolderPack: PackSource {
  public let descriptor: PackDescriptor
  public let folder: URL
  public let warnings: [String]

  private let manifest: PackManifest
  private let cache: SheetCache
  private let placeholder = PlaceholderPack()
  /// Roles the built-in sheet stands in for: undeclared, with no default-named file in the folder.
  private let substitutedSheets: Set<SheetRole>

  public init(folder: URL, cache: SheetCache) throws {
    guard let json = try? Data(contentsOf: folder.appending(path: "pack.json")) else {
      throw PackError.notAPack(folder.lastPathComponent)
    }
    let manifest: PackManifest
    do {
      manifest = try PackManifest(json: json)
    } catch {
      throw PackError.notAPack(folder.lastPathComponent)
    }
    self.manifest = manifest
    self.folder = folder
    self.cache = cache
    var descriptor = manifest.descriptor
    if descriptor.name.isEmpty {
      descriptor.name = folder.lastPathComponent
    }
    var substituted: Set<SheetRole> = []
    var warnings = manifest.warnings
    for role in SheetRole.allCases {
      guard var sheet = descriptor.sheets[role], !manifest.declaredSheets.contains(role) else { continue }
      guard !FileManager.default.fileExists(atPath: folder.appending(path: sheet.file).path) else { continue }
      substituted.insert(role)
      let dropped = "\(sheet.columns)x\(sheet.rows)"
      sheet.columns = SheetDescriptor.standardColumns
      sheet.rows = SheetDescriptor.standardRows
      descriptor.sheets[role] = sheet
      let placeholderGrid = "\(sheet.columns)x\(sheet.rows)"
      if dropped != placeholderGrid {
        warnings.append(
          "sheets.\(role.rawValue): the \(dropped) grid is ignored, \(sheet.file) is absent "
            + "so the placeholder sheet (\(placeholderGrid)) is used"
        )
      }
    }
    if substituted.contains(.point) {
      let count = descriptor.sheets[.point]?.frameCount ?? SheetDescriptor.standardFrameCount
      if !manifest.explicitPointFrames || descriptor.pointFrames.upperBound >= count {
        descriptor.pointFrames = PackDescriptor.defaultPointFrames(frameCount: count)
      }
    }
    if substituted.contains(.kick) {
      let count = descriptor.sheets[.kick]?.frameCount ?? SheetDescriptor.standardFrameCount
      if !manifest.explicitKickImpactFrame || descriptor.kickImpactFrame >= count {
        descriptor.kickImpactFrame = PackDescriptor.defaultKickImpactFrame(frameCount: count)
      }
    }
    substitutedSheets = substituted
    self.descriptor = descriptor
    self.warnings = warnings
  }

  public func sheet(for role: SheetRole) throws -> CGImage {
    guard let sheet = descriptor.sheets[role] else { throw PackError.missingSheet(role) }
    guard !substitutedSheets.contains(role) else { return try placeholder.sheet(for: role) }
    let file = folder.appending(path: sheet.file)
    guard FileManager.default.fileExists(atPath: file.path) else { throw PackError.missingFile(sheet.file) }
    let height = role == .explosion ? descriptor.explosionHeight : descriptor.characterHeight
    return try cache.sheet(for: role, at: file, columns: sheet.columns, rows: sheet.rows, frameHeight: Int(2 * height))
  }

  public func audio(for role: AudioRole) throws -> Data {
    guard let sound = descriptor.audio[role] else { throw PackError.missingAudio(role) }
    guard let file = try existingFile(sound.file, declared: manifest.declaredAudio.contains(role)) else {
      return try placeholder.audio(for: role)
    }
    return try Data(contentsOf: file)
  }

  /// The sound in the folder, `nil` for an undeclared name that is not there, and an error for a
  /// declared name that is not there.
  private func existingFile(_ name: String, declared: Bool) throws -> URL? {
    let url = folder.appending(path: name)
    if FileManager.default.fileExists(atPath: url.path) {
      return url
    }
    if declared {
      throw PackError.missingFile(name)
    }
    return nil
  }
}
