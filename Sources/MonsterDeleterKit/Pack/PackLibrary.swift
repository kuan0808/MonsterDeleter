import Foundation
import Observation
import os

/// The packs available to the show and the one currently chosen. Built-in packs are the folders in
/// the app bundle's `Resources/packs/`; user packs are the folders under
/// `~/Library/Application Support/MonsterDeleter/packs/`. The choice is persisted in
/// `UserDefaults`. Loading a pack decodes and slices its sheets, so it runs off the main actor;
/// `currentPack()` waits for a load in flight.
///
/// A pack that cannot be loaded is never papered over with the placeholder's stand-in art: the
/// failure is reported through `onLoadFailure`, and the app keeps wearing the pack that works, or
/// moves to the next one that loads when it was wearing nothing yet. With no pack at all, `current`
/// is `nil` and there is no show to play (`docs/adr/0007-no-placeholder-fallback.md`).
@MainActor
@Observable
public final class PackLibrary {
  public static let selectionKey = "selectedPack"

  /// The pack a fresh install wears: Kaiju, the monster the app is named after and the first pack
  /// its artwork was drawn for. A new user meets a real character rather than the stand-in art the
  /// self-test is written against. When the bundle holds no Kaiju, the first pack in the list does.
  public static let firstRunPackID: PackEntry.ID = "builtIn/kaiju"

  public private(set) var entries: [PackEntry] = []
  /// The chosen pack, which may still be loading; `nil` when there is no pack to choose.
  public private(set) var currentID: PackEntry.ID?
  /// The pack the app wears, once one has loaded.
  public private(set) var current: LoadedPack?
  /// A pack could not be loaded. The message names the pack and the reason.
  public var onLoadFailure: ((PackEntry, any Error) -> Void)?

  public let userPacksDirectory: URL
  /// Holds one slicing cache per pack, `<origin>/<folder name>/`.
  public let cacheDirectory: URL
  private let builtInPacksDirectory: URL?
  private let defaults: UserDefaults
  /// A headless launch (`LaunchDecision`) wears nothing: it forces the pack it wants itself.
  private let wearsStartingPack: Bool
  private let logger = Logger(subsystem: "io.github.kuan0808.MonsterDeleter", category: "pack")
  private var loadedEntry: PackEntry?
  private var loadedID: PackEntry.ID? { loadedEntry?.id }
  private var loading: Task<LoadedPack?, Never>?
  private var loadFailure: (generation: Int, error: any Error)?
  private var generation = 0

  public init(
    userPacksDirectory: URL,
    cacheDirectory: URL,
    builtInPacksDirectory: URL? = nil,
    defaults: UserDefaults = .standard,
    wearsStartingPack: Bool = true
  ) {
    self.userPacksDirectory = userPacksDirectory
    self.builtInPacksDirectory = builtInPacksDirectory
    self.cacheDirectory = cacheDirectory
    self.defaults = defaults
    self.wearsStartingPack = wearsStartingPack
    refresh()
  }

  /// The library at the standard locations under Application Support and the app bundle.
  public static func standard(wearsStartingPack: Bool = true) -> PackLibrary {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "MonsterDeleter")
    return PackLibrary(
      userPacksDirectory: support.appending(path: "packs"),
      cacheDirectory: support.appending(path: "cache"),
      builtInPacksDirectory: Bundle.main.resourceURL?.appending(path: "packs"),
      wearsStartingPack: wearsStartingPack
    )
  }

  public var currentEntry: PackEntry? {
    loadedEntry
  }

  /// There is another pack to swap to, so the ask bubble is worth a swap button.
  public var canSwap: Bool { entries.count > 1 }

  /// Whether `id` is the chosen pack and the one that is loaded, so the app really wears it.
  public func isCurrent(_ id: PackEntry.ID) -> Bool { currentID == id && loadedID == id }

  /// Rescans both locations. The chosen pack stays chosen if it is still there.
  public func refresh() {
    let previousEntry = entries.first { $0.id == currentID } ?? currentEntry
    var found: [PackEntry] = []
    if let builtInPacksDirectory {
      found += scan(builtInPacksDirectory, origin: .builtIn)
    }
    found += scan(userPacksDirectory, origin: .user)
    entries = found
    if currentID == nil || !entries.contains(where: { $0.id == currentID }) {
      wearStartingPack(preferred: previousEntry)
    }
  }

  /// The pack a launch starts on: the one the user last chose, else the first-run pack, else the
  /// first pack there is. It is not written to `UserDefaults`, so the saved choice keeps meaning
  /// "what the user picked" and a later first-run pack reaches everyone who never picked one.
  private func wearStartingPack(preferred: PackEntry? = nil) {
    guard wearsStartingPack, let start = preferred ?? startingPack() else {
      generation += 1
      loading = nil
      currentID = nil
      current = nil
      loadedEntry = nil
      return
    }
    select(start, reload: !entries.contains(where: { $0.id == start.id }), remembers: false)
  }

  private func startingPack() -> PackEntry? {
    if let saved = defaults.string(forKey: Self.selectionKey) {
      if let entry = entries.first(where: { $0.id == saved }) { return entry }
      let parts = saved.split(separator: "/", omittingEmptySubsequences: false)
      if parts.count == 2, let origin = PackEntry.Origin(rawValue: String(parts[0])),
        !parts[1].isEmpty, parts[1] != ".", parts[1] != "..",
        let directory = origin == .user ? userPacksDirectory : builtInPacksDirectory
      {
        let folderName = String(parts[1])
        return PackEntry(
          origin: origin,
          folderName: folderName,
          name: folderName,
          folder: directory.appending(path: folderName)
        )
      }
    }
    if let entry = entries.first(where: { $0.id == Self.firstRunPackID }) { return entry }
    if let folder = builtInPacksDirectory?.appending(path: "kaiju"),
      FileManager.default.fileExists(atPath: folder.path)
    {
      return PackEntry(origin: .builtIn, folderName: "kaiju", name: "Kaiju", folder: folder)
    }
    return entries.first
  }

  /// Makes `id` the chosen pack, remembers it and loads it in the background.
  public func select(_ id: PackEntry.ID) {
    select(id, reload: false)
  }

  /// `reload` reads the folder again even when its pack is the loaded one, which an install of the
  /// current pack needs: the folder's contents changed under the same identity. An install reports
  /// the failure itself, so it turns `reportsFailure` off to avoid a second report. The generation
  /// it returns names the load it started, so an install can tell its own outcome from a choice
  /// made while it was loading.
  @discardableResult
  private func select(
    _ id: PackEntry.ID,
    reload: Bool,
    reportsFailure: Bool = true,
    remembers: Bool = true
  ) -> Int {
    guard let entry = entries.first(where: { $0.id == id }) else { return generation }
    return select(entry, reload: reload, reportsFailure: reportsFailure, remembers: remembers)
  }

  @discardableResult
  private func select(
    _ entry: PackEntry,
    reload: Bool,
    reportsFailure: Bool = true,
    remembers: Bool = true
  ) -> Int {
    let id = entry.id
    currentID = id
    // A newer choice outranks any load still in flight, including choosing the loaded pack back.
    generation += 1
    if id == loadedID, !reload {
      loading = nil
      if remembers { remember(id) }
      return generation
    }
    let generation = generation
    loading = Task { [weak self] in
      await self?.load(entry, generation: generation, reportsFailure: reportsFailure, remembers: remembers)
    }
    return generation
  }

  /// Loads `entry`. A failure is reported and, while the app is wearing nothing at all, the next
  /// pack that does load takes over: a broken pack must not leave a new user with no show, and it
  /// must not be papered over either. Only the pack the user actually chose is remembered, only
  /// its own error is the one an install hears about, and the report waits until the fall-forward
  /// has settled, so what it says the app is wearing is what the app is wearing.
  private func load(
    _ entry: PackEntry,
    generation: Int,
    reportsFailure: Bool,
    remembers: Bool
  ) async -> LoadedPack? {
    var candidate: PackEntry? = entry
    var tried: Set<PackEntry.ID> = []
    var remembers = remembers
    var failure: (entry: PackEntry, error: any Error)?
    var loaded: LoadedPack?
    while let entry = candidate {
      tried.insert(entry.id)
      do {
        let pack = try await Self.load(entry, cache: cache(for: entry))
        guard generation == self.generation else { return await currentPack() }
        current = pack
        currentID = entry.id
        loadedEntry = entry
        loading = nil
        if remembers { remember(entry.id) }
        loaded = pack
        break
      } catch {
        logger.error(
          "Cannot load pack \(entry.id, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        guard generation == self.generation else { return await currentPack() }
        if failure == nil {
          loadFailure = (generation, error)
          failure = (entry, error)
        }
        candidate =
          loadedID == nil || !entries.contains(where: { $0.id == loadedID })
          ? entries.first { $0.id == Self.firstRunPackID && !tried.contains($0.id) }
            ?? entries.first { !tried.contains($0.id) }
          : nil
        remembers = false
      }
    }
    if loaded == nil {
      currentID = loadedID
      loading = nil
    }
    if reportsFailure, let failure {
      onLoadFailure?(failure.entry, failure.error)
    }
    return loaded ?? current
  }

  private func remember(_ id: PackEntry.ID) {
    defaults.set(id, forKey: Self.selectionKey)
  }

  /// The chosen pack, once loaded, or `nil` when no pack could be loaded at all.
  public func currentPack() async -> LoadedPack? {
    if let loading {
      return await loading.value
    }
    return current
  }

  /// Loads the pack `id` names without choosing it or disturbing the current one, for a
  /// `MONSTER_AUTOPLAY_PACK` run. `nil` when the library holds no such pack.
  public func pack(for id: PackEntry.ID) async throws -> LoadedPack? {
    guard let entry = entries.first(where: { $0.id == id }) else { return nil }
    return try await Self.load(entry, cache: cache(for: entry))
  }

  private func cache(for entry: PackEntry) -> SheetCache {
    SheetCache(directory: cacheDirectory.appending(path: entry.origin.rawValue).appending(path: entry.folderName))
  }

  /// The entry after `id`, wrapping round; used by the swap button.
  public func entry(after id: PackEntry.ID) -> PackEntry? {
    guard let index = entries.firstIndex(where: { $0.id == id }) else { return entries.first }
    return entries[(index + 1) % entries.count]
  }

  // MARK: Installing

  /// Installs a dropped zip as a user pack, rescans and chooses it. It returns once its own load
  /// has finished and says whether the installed pack ended up current, since a choice made
  /// meanwhile outranks the install; only that load's own error is thrown.
  public func install(zipAt url: URL) async throws -> PackInstallation {
    let folder = try await Self.install(PackArchive(url: url), into: userPacksDirectory)
    refresh()
    let id = PackEntry.id(origin: .user, folderName: folder.lastPathComponent)
    guard let entry = entries.first(where: { $0.id == id }) else { throw PackInstallError.invalidManifest }
    let generation = select(id, reload: true, reportsFailure: false)
    _ = await currentPack()
    if let failure = loadFailure, failure.generation == generation {
      loadFailure = nil
      throw failure.error
    }
    return PackInstallation(entry: entry, isCurrent: isCurrent(id))
  }

  @concurrent
  private nonisolated static func install(_ archive: PackArchive, into directory: URL) async throws -> URL {
    try archive.install(into: directory)
  }

  // MARK: Loading

  @concurrent
  private nonisolated static func load(_ entry: PackEntry, cache: SheetCache) async throws -> LoadedPack {
    let source = try FolderPack(folder: entry.folder, cache: cache)
    let logger = Logger(subsystem: "io.github.kuan0808.MonsterDeleter", category: "pack")
    for warning in source.warnings {
      logger.warning("\(entry.id, privacy: .public) pack.json \(warning, privacy: .public)")
    }
    return try LoadedPack(source: source)
  }

  /// The folders under `directory` with a readable `pack.json`, by name.
  private func scan(_ directory: URL, origin: PackEntry.Origin) -> [PackEntry] {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
    var found: [PackEntry] = []
    for name in names.sorted() where !name.hasPrefix(".") {
      let folder = directory.appending(path: name)
      guard let json = try? Data(contentsOf: folder.appending(path: "pack.json")) else { continue }
      guard let manifest = try? PackManifest(json: json) else {
        logger.warning("Skipping \(folder.lastPathComponent, privacy: .public): pack.json is not a JSON object")
        continue
      }
      let name = manifest.descriptor.name.isEmpty ? folder.lastPathComponent : manifest.descriptor.name
      found.append(PackEntry(origin: origin, folderName: folder.lastPathComponent, name: name, folder: folder))
    }
    return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}
