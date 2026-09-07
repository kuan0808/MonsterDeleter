import AppKit

/// AppKit bridge for native trash-only deletion, with one completion for the whole batch.
/// Finder owns restoration. Never a permanent delete.
public enum TrashService {
  @MainActor
  public static func trash(_ urls: [URL]) async -> TrashOutcome {
    await withCheckedContinuation { continuation in
      NSWorkspace.shared.recycle(urls) { trashed, error in
        continuation.resume(returning: TrashOutcome(requested: urls, trashed: trashed, error: error))
      }
    }
  }
}
