import AppKit
import Testing

@testable import MonsterDeleterKit

@Suite("ShowDirector", .serialized)
@MainActor
struct ShowDirectorTests {
  @Test("delayed Trash completion keeps its own aim while another show is unconfirmed", arguments: [0, 2])
  func completionOwnsItsAim(resolvedIcons: Int) async throws {
    _ = NSApplication.shared
    let pack = try LoadedPack(source: FastPack())
    let system = DelayedTrash()
    let director = ShowDirector(
      pack: pack,
      activation: AppActivation(activateApp: {}, isAppActive: { false }),
      trash: { await system.trash($0) }
    )
    director.playsSound = false
    var completions: [(ShowPhase, TrashOutcome?, UnaimedFan)] = []
    director.onFinished = { completions.append(($0, $1, $2)) }
    defer {
      system.release()
      director.cancel()
    }
    let folder = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: ".build/show-fixture")
    let first = [folder.appending(path: "first"), folder.appending(path: "second")]
    let second = (1...3).map { folder.appending(path: "next-\($0)") }
    let point = CGPoint(x: 400, y: 300)
    let rect = CGRect(x: 384, y: 284, width: 32, height: 32)
    director.summon(first, aim: TargetAim(point: point, iconRects: Array(repeating: rect, count: resolvedIcons)))
    try await waitUntil { director.phase == .asking }
    director.confirm()
    try await waitUntil { director.phase == .done && system.pending != nil }
    #expect(completions.isEmpty)
    #expect(!director.isRunning)
    director.summon(second, aim: TargetAim(point: point, iconRects: resolvedIcons == 0 ? [rect] : []))
    try await waitUntil { director.phase == .asking }
    system.release()
    try await waitUntil { completions.count == 1 }
    #expect(director.isRunning)
    #expect(completions[0].0 == .done)
    #expect(completions[0].1 == TrashOutcome(trashed: [:], failures: []))
    #expect(completions[0].2 == UnaimedFan(targetCount: 2, resolvedIcons: resolvedIcons))
    #expect(completions[0].2.landedInARing(endingIn: completions[0].0) == (resolvedIcons == 0))
    #expect(system.requested == [first])
    director.cancel()
    try await waitUntil { completions.count == 2 }
    #expect(completions[1].0 == .cancelled)
    #expect(completions[1].1 == nil)
    #expect(completions[1].2 == UnaimedFan(targetCount: 3, resolvedIcons: resolvedIcons == 0 ? 1 : 0))
    #expect(!completions[1].2.landedInARing(endingIn: completions[1].0))
    #expect(system.requested == [first])
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition())
  }

  @MainActor
  private final class DelayedTrash {
    var pending: CheckedContinuation<TrashOutcome, Never>?
    var requested: [[URL]] = []

    func trash(_ urls: [URL]) async -> TrashOutcome {
      requested.append(urls)
      return await withCheckedContinuation { pending = $0 }
    }

    func release() {
      pending?.resume(returning: TrashOutcome(trashed: [:], failures: []))
      pending = nil
    }
  }

  private struct FastPack: PackSource {
    var descriptor: PackDescriptor {
      var descriptor = PackDescriptor.placeholder
      descriptor.framesPerSecond = 60
      descriptor.walkSeconds = 0.01
      descriptor.flySeconds = 0.01
      return descriptor
    }

    func sheet(for role: SheetRole) throws -> CGImage { try PlaceholderPack().sheet(for: role) }
    func audio(for role: AudioRole) throws -> Data { try PlaceholderPack().audio(for: role) }
  }
}
