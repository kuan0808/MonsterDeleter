import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The built-in pack: sheets painted on first use, sounds synthesised on first use.
///
/// It goes through the same sheet-slicing pipeline a folder pack will, so the whole show runs end
/// to end before any real artwork exists.
public struct PlaceholderPack: PackSource {
  public let descriptor: PackDescriptor = .placeholder

  public init() {}

  public func sheet(for role: SheetRole) throws -> CGImage {
    guard let grid = descriptor.sheets[role] else { throw PackError.missingSheet(role) }
    guard let image = PlaceholderSheetRenderer.render(role: role, columns: grid.columns, rows: grid.rows) else {
      throw PackError.cannotRender(role)
    }
    return image
  }

  public func audio(for role: AudioRole) throws -> Data {
    switch role {
    case .bgm: return ToneSynthesizer.backgroundLoop()
    case .voice: return ToneSynthesizer.voice()
    case .explosion: return ToneSynthesizer.explosion()
    }
  }

  /// Writes the pack as a folder (`pack.json`, six PNG sheets, three WAV files): the template for
  /// authoring a pack, and the source of the user-pack evidence.
  public func write(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(descriptor).write(to: folder.appending(path: "pack.json"))
    for role in SheetRole.allCases {
      guard let sheet = descriptor.sheets[role] else { throw PackError.missingSheet(role) }
      let url = folder.appending(path: sheet.file)
      guard
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
      else { throw CocoaError(.fileWriteUnknown) }
      CGImageDestinationAddImage(destination, try self.sheet(for: role), nil)
      guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
    for role in AudioRole.allCases {
      guard let sound = descriptor.audio[role] else { throw PackError.missingAudio(role) }
      try audio(for: role).write(to: folder.appending(path: sound.file))
    }
  }
}
