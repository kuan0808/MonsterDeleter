import CoreGraphics
import Foundation

/// Where a pack's bytes come from: generated in memory (`PlaceholderPack`) or read from a pack
/// folder (`FolderPack`). `LoadedPack` slices and caches whatever a source hands it.
public protocol PackSource: Sendable {
  var descriptor: PackDescriptor { get }
  func sheet(for role: SheetRole) throws -> CGImage
  func audio(for role: AudioRole) throws -> Data
}
