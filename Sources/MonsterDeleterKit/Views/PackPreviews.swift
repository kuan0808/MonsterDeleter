import CoreGraphics
import Observation

/// One frame of each character, so the picker can show the characters themselves rather than a
/// list of their names. Loading a pack decodes and slices its sheets, so this happens in the
/// background, one pack at a time, only while the Settings window is open, and only once per pack:
/// the slicing cache makes the second time cheap.
@MainActor
@Observable
public final class PackPreviews {
  public private(set) var frames: [PackEntry.ID: CGImage] = [:]
  private var asked: Set<PackEntry.ID> = []

  public init() {}

  /// `reloading` names the packs whose folders have changed under the same id, which an install
  /// does: their artwork is read again rather than taken from the first time round.
  public func load(_ entries: [PackEntry], from library: PackLibrary, reloading: Set<PackEntry.ID> = []) async {
    asked.subtract(reloading)
    for entry in entries where !asked.contains(entry.id) {
      asked.insert(entry.id)
      if library.isCurrent(entry.id), let current = library.current {
        frames[entry.id] = current.frames(for: .point).first
        continue
      }
      guard let pack = try? await library.pack(for: entry.id) else {
        frames[entry.id] = nil
        continue
      }
      frames[entry.id] = pack.frames(for: .point).first
    }
  }
}
