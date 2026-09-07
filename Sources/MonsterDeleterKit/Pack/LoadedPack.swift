import CoreGraphics
import Foundation

/// A pack ready to play: every sheet sliced into frames, every sound as data.
public struct LoadedPack: Sendable {
  public let descriptor: PackDescriptor
  public let choreography: Choreography
  public let frames: [SheetRole: [CGImage]]
  public let audio: [AudioRole: Data]
  public init(source: some PackSource) throws {
    descriptor = source.descriptor
    choreography = Choreography(pack: source.descriptor)
    var frames: [SheetRole: [CGImage]] = [:]
    for role in SheetRole.allCases {
      guard let sheet = source.descriptor.sheets[role] else { throw PackError.missingSheet(role) }
      let image = try source.sheet(for: role)
      guard let sliced = SheetSlicer.frames(of: image, columns: sheet.columns, rows: sheet.rows) else {
        throw PackError.cannotSlice(role)
      }
      frames[role] = sliced
    }
    self.frames = frames
    var audio: [AudioRole: Data] = [:]
    for role in AudioRole.allCases {
      guard source.descriptor.audio[role] != nil else { throw PackError.missingAudio(role) }
      audio[role] = try source.audio(for: role)
    }
    self.audio = audio
  }

  public func frames(for role: SheetRole) -> [CGImage] { frames[role] ?? [] }

  /// Width divided by height of the first frame of a sheet.
  public func aspect(of role: SheetRole) -> CGFloat {
    guard let first = frames[role]?.first, first.height > 0 else { return 1 }
    return CGFloat(first.width) / CGFloat(first.height)
  }
}
