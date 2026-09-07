import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("PackLibrary")
@MainActor
struct PackLibraryTests {
  let root: URL
  let packs: URL
  let builtIn: URL
  let defaults: UserDefaults
  let suite: String

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "PackLibraryTests-\(UUID().uuidString)")
    packs = root.appending(path: "packs")
    builtIn = root.appending(path: "built-in")
    try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
    suite = "PackLibraryTests-\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: suite))
  }

  private func makeLibrary() -> PackLibrary {
    PackLibrary(
      userPacksDirectory: packs,
      cacheDirectory: root.appending(path: "cache"),
      builtInPacksDirectory: builtIn,
      defaults: defaults
    )
  }

  private func addPack(_ folder: String, manifest: String = "{}") throws {
    try write(manifest, to: packs.appending(path: folder))
  }

  /// A built-in pack of the app bundle. `kaiju` is the one a fresh install starts on.
  private func addBuiltInPack(_ folder: String, manifest: String = "{}") throws {
    try write(manifest, to: builtIn.appending(path: folder))
  }

  private func write(_ manifest: String, to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(manifest.utf8).write(to: folder.appending(path: "pack.json"))
  }

  /// A pack whose manifest names a sheet file the folder does not hold.
  private static let brokenManifest = #"{"name": "Broken", "sheets": {"walk": {"file": "nope.png"}}}"#

  @Test("packs are the built-in folders then the user folders, each by name")
  func discovery() throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    try addPack("zebra", manifest: #"{"name": "Zebra"}"#)
    try addPack("alpha")
    try addPack("broken", manifest: "not json")
    try FileManager.default.createDirectory(at: packs.appending(path: "junk"), withIntermediateDirectories: true)
    try Data().write(to: packs.appending(path: "stray.txt"))
    let library = makeLibrary()
    #expect(library.entries.map(\.id) == ["builtIn/kaiju", "user/alpha", "user/zebra"])
    #expect(library.entries.map(\.name) == ["Kaiju", "alpha", "Zebra"])
    #expect(library.entries[0].origin == .builtIn)
    #expect(library.entries[1].origin == .user)
    #expect(library.entries[1].folder == packs.appending(path: "alpha"))
  }

  @Test("the placeholder is not a pack anyone can choose")
  func placeholderIsNotListed() throws {
    try addBuiltInPack("kaiju")
    let library = makeLibrary()
    #expect(!library.entries.contains { $0.id.contains("placeholder") })
  }

  @Test("a fresh install starts on Kaiju, not on whichever pack sorts first")
  func firstRunPack() async throws {
    try addBuiltInPack("cat", manifest: #"{"name": "Cat"}"#)
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    try addBuiltInPack("ufo", manifest: #"{"name": "UFO"}"#)
    let library = makeLibrary()
    #expect(library.entries.first?.id == "builtIn/cat", "Cat sorts first, so the choice is deliberate")
    #expect(library.currentID == "builtIn/kaiju")
    #expect(await library.currentPack()?.descriptor.name == "Kaiju")
  }

  @Test("without Kaiju a fresh install starts on the first pack there is")
  func firstRunFallsToTheFirstPack() async throws {
    try addBuiltInPack("cat", manifest: #"{"name": "Cat"}"#)
    let library = makeLibrary()
    #expect(library.currentID == "builtIn/cat")
    #expect(await library.currentPack()?.descriptor.name == "Cat")
  }

  @Test("a saved choice wins over the first-run pack")
  func savedChoiceWins() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    try addPack("mine", manifest: #"{"name": "Mine"}"#)
    defaults.set("user/mine", forKey: PackLibrary.selectionKey)
    let library = makeLibrary()
    #expect(library.currentID == "user/mine")
    #expect(await library.currentPack()?.descriptor.name == "Mine")
  }

  @Test("a first-run pack that cannot be loaded is reported and the next pack that can is worn")
  func firstRunPackIsBroken() async throws {
    try addBuiltInPack("kaiju", manifest: Self.brokenManifest)
    try addBuiltInPack("ufo", manifest: #"{"name": "UFO"}"#)
    let library = makeLibrary()
    var reported: (PackEntry, any Error)?
    var wearing: PackEntry?
    library.onLoadFailure = {
      reported = ($0, $1)
      wearing = library.currentEntry
    }
    let pack = await library.currentPack()
    #expect(pack?.descriptor.name == "UFO", "the app wears a pack that works")
    #expect(library.currentID == "builtIn/ufo")
    #expect(reported?.0.id == "builtIn/kaiju", "the user is told which pack failed and why")
    #expect(reported?.1 as? PackError == .missingFile("nope.png"))
    #expect(wearing?.id == "builtIn/ufo", "the report names the character the fall-forward put on")
  }

  @Test(
    "unreadable first-run character information is reported after replacement settles",
    arguments: ["malformed", "unreadable"],
    [true, false]
  )
  func firstRunDiscoveryFailure(kind: String, hasReplacement: Bool) async throws {
    if kind == "malformed" {
      try addBuiltInPack("kaiju", manifest: "not JSON")
    } else {
      try FileManager.default.createDirectory(
        at: builtIn.appending(path: "kaiju/pack.json"),
        withIntermediateDirectories: true
      )
    }
    if hasReplacement { try addBuiltInPack("cat", manifest: #"{"name":"Cat"}"#) }
    let library = makeLibrary()
    var failedName: String?
    var failure: PackError?
    var replacement: String?
    library.onLoadFailure = { entry, error in
      failedName = entry.name
      failure = error as? PackError
      replacement = library.currentEntry?.name
    }
    #expect(await library.currentPack()?.descriptor.name == (hasReplacement ? "Cat" : nil))
    #expect(failedName == "Kaiju")
    #expect(failure == .notAPack("kaiju"))
    #expect(replacement == (hasReplacement ? "Cat" : nil))
    #expect(defaults.string(forKey: PackLibrary.selectionKey) == nil)
  }

  @Test("no pack at all leaves the app wearing none rather than stand-in art")
  func noPackAtAll() async throws {
    let library = makeLibrary()
    #expect(library.entries.isEmpty)
    #expect(library.currentID == nil)
    #expect(await library.currentPack() == nil)
  }

  @Test("every pack failing to load leaves the app wearing none, with the first failure reported")
  func everyPackIsBroken() async throws {
    try addBuiltInPack("kaiju", manifest: Self.brokenManifest)
    let library = makeLibrary()
    var reported: [PackEntry.ID] = []
    var wearing: [PackEntry?] = []
    library.onLoadFailure = { entry, _ in
      reported.append(entry.id)
      wearing.append(library.currentEntry)
    }
    #expect(await library.currentPack() == nil)
    #expect(library.currentID == nil)
    #expect(reported == ["builtIn/kaiju"])
    #expect(wearing == [nil], "there is no character to name as the one in use")
  }

  @Test("selecting a pack loads it, remembers it and a new library restores it")
  func selectionPersists() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    try addPack("sea", manifest: #"{"name": "Sea Monster", "texts": {"bubble": "This one?"}}"#)
    let library = makeLibrary()
    library.select("user/sea")
    #expect(library.currentID == "user/sea")
    let loaded = try #require(await library.currentPack())
    #expect(loaded.descriptor.name == "Sea Monster")
    #expect(loaded.descriptor.texts.bubble == "This one?")
    #expect(loaded.frames(for: .walk).count == 15, "sheets a pack leaves out come from the built-in ones")
    let restored = makeLibrary()
    #expect(restored.currentID == "user/sea")
    #expect(await restored.currentPack()?.descriptor.name == "Sea Monster")
  }

  @Test(
    "a missing or unreadable saved character is reported after a working replacement loads",
    arguments: ["missing", "unreadable", "malformed"]
  )
  func staleSelection(kind: String) async throws {
    try addBuiltInPack("cat", manifest: #"{"name": "Cat"}"#)
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    if kind == "unreadable" {
      try FileManager.default.createDirectory(
        at: packs.appending(path: "gone/pack.json"),
        withIntermediateDirectories: true
      )
    } else if kind == "malformed" {
      try addPack("gone", manifest: "not JSON")
    }
    defaults.set("user/gone", forKey: PackLibrary.selectionKey)
    let library = makeLibrary()
    var report: LoadFailureQueue.Report?
    library.onLoadFailure = { entry, error in
      report = CharacterFailure.report(name: entry.name, error: error, wearing: library.currentEntry?.name)
    }
    #expect(await library.currentPack()?.descriptor.name == "Kaiju")
    #expect(library.currentID == "builtIn/kaiju")
    #expect(report?.title == "\"gone\" could not be loaded")
    #expect(
      report?.message == """
        This character's information is missing or unreadable.

        MonsterDeleter is using Kaiju instead.

        Install it again, or pick another character in Settings.
        """
    )
    #expect(defaults.string(forKey: PackLibrary.selectionKey) == "user/gone")
  }

  @Test("a missing saved character is reported even when no other character exists")
  func missingWithoutReplacement() async throws {
    defaults.set("user/gone", forKey: PackLibrary.selectionKey)
    let library = makeLibrary()
    var report: LoadFailureQueue.Report?
    library.onLoadFailure = { entry, error in
      report = CharacterFailure.report(name: entry.name, error: error, wearing: library.currentEntry?.name)
    }
    #expect(await library.currentPack() == nil)
    #expect(library.currentID == nil)
    #expect(report?.title == "\"gone\" could not be loaded")
    #expect(
      report?.message == """
        This character's information is missing or unreadable.

        No other character could be loaded either.

        Install it again, or pick another character in Settings.
        """
    )
  }

  @Test("a pack that fails to load keeps the working one, reports the failure and is not remembered")
  func loadFailure() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    try addPack("bad", manifest: Self.brokenManifest)
    let library = makeLibrary()
    _ = await library.currentPack()
    library.select("builtIn/kaiju")
    var reported: (PackEntry, any Error)?
    var wearing: PackEntry?
    library.onLoadFailure = {
      reported = ($0, $1)
      wearing = library.currentEntry
    }
    library.select("user/bad")
    let pack = await library.currentPack()
    #expect(pack?.descriptor.name == "Kaiju", "the pack that works stays on")
    #expect(library.currentID == "builtIn/kaiju")
    #expect(reported?.0.id == "user/bad")
    #expect(wearing?.id == "builtIn/kaiju", "the failure names the character in use, not the one that failed")
    #expect(reported?.1 as? PackError == .missingFile("nope.png"))
    #expect(
      defaults.string(forKey: PackLibrary.selectionKey) == "builtIn/kaiju",
      "a pack that fails to load is never remembered as the choice"
    )
  }

  @Test("a pack the fall-forward lands on is not saved as the user's choice")
  func fallForwardIsNotRemembered() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    try addPack("bad", manifest: Self.brokenManifest)
    let library = makeLibrary()
    var reported: (PackEntry, any Error)?
    library.onLoadFailure = { reported = ($0, $1) }
    // The starting pack is still loading, so the app is wearing nothing when the broken one is
    // chosen: its failure falls forward to Kaiju, which the user never picked.
    library.select("user/bad")
    #expect(await library.currentPack()?.descriptor.name == "Kaiju")
    #expect(reported?.0.id == "user/bad")
    #expect(
      defaults.string(forKey: PackLibrary.selectionKey) == nil,
      "only a pack the user picked and that loaded is remembered"
    )
  }

  @Test("next cycles through the entries and wraps")
  func nextWraps() throws {
    try addBuiltInPack("kaiju")
    try addPack("a")
    try addPack("b")
    let library = makeLibrary()
    #expect(library.entry(after: "builtIn/kaiju")?.id == "user/a")
    #expect(library.entry(after: "user/a")?.id == "user/b")
    #expect(library.entry(after: "user/b")?.id == "builtIn/kaiju")
    #expect(library.entry(after: "user/unknown")?.id == "builtIn/kaiju", "an unknown pack starts the list again")
  }

  @Test("there is nothing to swap to until a second pack shows up")
  func canSwap() throws {
    try addBuiltInPack("kaiju")
    let library = makeLibrary()
    #expect(!library.canSwap)
    try addPack("sea")
    library.refresh()
    #expect(library.canSwap)
  }

  @Test("refresh picks up a pack added since and keeps the selection")
  func refresh() throws {
    try addBuiltInPack("kaiju")
    let library = makeLibrary()
    #expect(library.entries.count == 1)
    try addPack("late")
    library.refresh()
    #expect(library.entries.map(\.id) == ["builtIn/kaiju", "user/late"])
    #expect(library.currentID == "builtIn/kaiju")
  }

  @Test("a pack whose folder disappears hands the app back to the first-run pack")
  func currentPackRemoved() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    try addPack("sea", manifest: #"{"name": "Sea Monster"}"#)
    let library = makeLibrary()
    library.select("user/sea")
    _ = await library.currentPack()
    var report: LoadFailureQueue.Report?
    library.onLoadFailure = { entry, error in
      report = CharacterFailure.report(name: entry.name, error: error, wearing: library.currentEntry?.name)
    }
    try FileManager.default.removeItem(at: packs.appending(path: "sea"))
    library.refresh()
    #expect(await library.currentPack()?.descriptor.name == "Kaiju")
    #expect(library.currentID == "builtIn/kaiju")
    #expect(report?.title == "\"Sea Monster\" could not be loaded")
    #expect(report?.message.contains("MonsterDeleter is using Kaiju instead.") == true)
  }

  @Test("a removed folder keeps its loaded character when no replacement works")
  func removedWithoutWorkingReplacement() async throws {
    try addPack("sea", manifest: #"{"name": "Sea Monster"}"#)
    let library = makeLibrary()
    _ = await library.currentPack()
    var wearing: String?
    library.onLoadFailure = { _, _ in wearing = library.currentEntry?.name }
    try FileManager.default.removeItem(at: packs.appending(path: "sea"))
    library.refresh()
    #expect(await library.currentPack()?.descriptor.name == "Sea Monster")
    #expect(library.currentEntry?.name == "Sea Monster")
    #expect(wearing == "Sea Monster")
  }

  @Test("installing a zip adds the pack and chooses it")
  func install() async throws {
    let zip = root.appending(path: "Sea Monster.zip")
    try TestZip.write([("pack.json", Data(#"{"name": "Sea Monster"}"#.utf8))], to: zip)
    let library = makeLibrary()
    let installation = try await library.install(zipAt: zip)
    #expect(installation.entry.id == "user/Sea-Monster")
    #expect(installation.entry.name == "Sea Monster")
    #expect(installation.isCurrent)
    #expect(library.entries.map(\.id) == ["user/Sea-Monster"])
    #expect(library.currentID == "user/Sea-Monster")
    #expect(await library.currentPack()?.descriptor.name == "Sea Monster")
  }

  @Test("re-installing the current pack dresses the app in the new contents")
  func reinstallReloads() async throws {
    let zip = root.appending(path: "kaiju.zip")
    try TestZip.write([("pack.json", Data(#"{"name": "Kaiju", "texts": {"bubble": "One?"}}"#.utf8))], to: zip)
    let library = makeLibrary()
    _ = try await library.install(zipAt: zip)
    #expect(await library.currentPack()?.descriptor.texts.bubble == "One?")
    try TestZip.write([("pack.json", Data(#"{"name": "Kaiju", "texts": {"bubble": "Two?"}}"#.utf8))], to: zip)
    _ = try await library.install(zipAt: zip)
    #expect(library.currentID == "user/kaiju")
    #expect(await library.currentPack()?.descriptor.texts.bubble == "Two?")
  }

  @Test("an installed pack that cannot be loaded reports the load failure to the installer")
  func installReportsALoadFailure() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    let zip = root.appending(path: "broken.zip")
    try TestZip.write(
      [
        ("pack.json", Data(#"{"name": "Broken", "sheets": {"walk": {"file": "walk.png"}}}"#.utf8)),
        ("walk.png", Data("not an image".utf8)),
      ],
      to: zip
    )
    let library = makeLibrary()
    _ = await library.currentPack()
    var reported: (PackEntry, any Error)?
    library.onLoadFailure = { reported = ($0, $1) }
    await #expect(throws: PackError.cannotDecode("walk.png")) { try await library.install(zipAt: zip) }
    #expect(library.currentID == "builtIn/kaiju", "the previous pack stays on")
    #expect(await library.currentPack()?.descriptor.name == "Kaiju")
    #expect(reported == nil, "the installer reports it, so there is no second report")
    #expect(
      FileManager.default.fileExists(atPath: packs.appending(path: "broken/pack.json").path),
      "the folder is installed even though it cannot be loaded"
    )
  }

  @Test("an install throws its own pack's reason, not one from the fall-forward after it")
  func installThrowsItsOwnError() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju", "sheets": {"walk": {"file": "gone.png"}}}"#)
    let zip = root.appending(path: "broken.zip")
    try TestZip.write(
      [
        ("pack.json", Data(#"{"name": "Broken", "sheets": {"walk": {"file": "walk.png"}}}"#.utf8)),
        ("walk.png", Data("not an image".utf8)),
      ],
      to: zip
    )
    let library = makeLibrary()
    #expect(await library.currentPack() == nil, "nothing loads, so the install starts wearing nothing")
    await #expect(throws: PackError.cannotDecode("walk.png")) { try await library.install(zipAt: zip) }
  }

  @Test("a pack chosen while an install is loading outranks it, and the install says so")
  func installSwitchedAwayFrom() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    let zip = root.appending(path: "sea.zip")
    try TestZip.write([("pack.json", Data(#"{"name": "Sea Monster"}"#.utf8))], to: zip)
    let library = makeLibrary()
    _ = await library.currentPack()
    let installing = Task { try await library.install(zipAt: zip) }
    while library.currentID != "user/sea" {
      await Task.yield()
    }
    library.select("builtIn/kaiju")
    let installation = try await installing.value
    #expect(installation.entry.id == "user/sea")
    #expect(!installation.isCurrent, "the later choice wins")
    #expect(library.currentID == "builtIn/kaiju")
    #expect(await library.currentPack()?.descriptor.name == "Kaiju")
    #expect(FileManager.default.fileExists(atPath: packs.appending(path: "sea/pack.json").path))
  }

  @Test("another pack's load failure during an install is not blamed on the install")
  func installNotBlamedForAnotherFailure() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    try addPack("bad", manifest: Self.brokenManifest)
    let zip = root.appending(path: "sea.zip")
    try TestZip.write([("pack.json", Data(#"{"name": "Sea Monster"}"#.utf8))], to: zip)
    let library = makeLibrary()
    _ = await library.currentPack()
    var reported: (PackEntry, any Error)?
    library.onLoadFailure = { reported = ($0, $1) }
    let installing = Task { try await library.install(zipAt: zip) }
    while library.currentID != "user/sea" {
      await Task.yield()
    }
    library.select("user/bad")
    let installation = try await installing.value
    #expect(installation.entry.id == "user/sea")
    #expect(!installation.isCurrent)
    _ = await library.currentPack()
    #expect(reported?.0.id == "user/bad", "the other pack's failure is reported as its own")
    #expect(reported?.1 as? PackError == .missingFile("nope.png"))
  }

  @Test("every dropped file gets its own line, in drop order")
  func outcomePerDroppedFile() async throws {
    let rejected = root.appending(path: "art.zip")
    try TestZip.write([("walk.png", Data())], to: rejected)
    let good = root.appending(path: "Kaiju.zip")
    try TestZip.write([("pack.json", Data(#"{"name": "Kaiju"}"#.utf8))], to: good)
    let notAZip = root.appending(path: "notes.txt")
    try Data("hello".utf8).write(to: notAZip)
    let library = makeLibrary()
    let outcomes = await InstallOutcome.outcomes(for: [rejected, good, notAZip]) {
      try await library.install(zipAt: $0)
    } isCurrent: {
      library.isCurrent($0)
    } wearing: {
      await library.currentPack()?.descriptor.name
    }
    #expect(outcomes.count == 3)
    #expect(outcomes[0].isFailure)
    #expect(outcomes[0].message.hasPrefix("art.zip: "), "the failure names its file: \(outcomes[0].message)")
    #expect(
      outcomes[0].message
        == "art.zip: This zip has no readable character information. MonsterDeleter is using Kaiju instead. Get a new copy and try Choose Zip in Settings."
    )
    #expect(outcomes[1] == InstallOutcome(message: "Installed Kaiju. It is now your character.", isFailure: false))
    #expect(outcomes[2] == InstallOutcome(message: "notes.txt is not a zip archive.", isFailure: true))
    #expect(library.currentID == "user/Kaiju")
  }

  @Test("dropping two packs at once claims the current pack only for the one that ends up current")
  func onlyTheLastInstallClaimsTheCurrentPack() async throws {
    let alpha = root.appending(path: "Alpha.zip")
    try TestZip.write([("pack.json", Data(#"{"name": "Alpha"}"#.utf8))], to: alpha)
    let beta = root.appending(path: "Beta.zip")
    try TestZip.write([("pack.json", Data(#"{"name": "Beta"}"#.utf8))], to: beta)
    let library = makeLibrary()
    let outcomes = await InstallOutcome.outcomes(for: [alpha, beta]) {
      try await library.install(zipAt: $0)
    } isCurrent: {
      library.isCurrent($0)
    } wearing: {
      await library.currentPack()?.descriptor.name
    }
    #expect(
      outcomes == [
        InstallOutcome(message: "Installed Alpha.", isFailure: false),
        InstallOutcome(message: "Installed Beta. It is now your character.", isFailure: false),
      ]
    )
    #expect(library.currentID == "user/Beta")
  }

  @Test("failed artwork installation reports the settled working character", arguments: [true, false])
  func failedInstallReportsReplacement(hasReplacement: Bool) async throws {
    if hasReplacement { try addBuiltInPack("kaiju", manifest: #"{"name":"Kaiju"}"#) }
    let zip = root.appending(path: "broken.zip")
    try TestZip.write(
      [
        ("pack.json", Data(#"{"name":"Broken","sheets":{"walk":{"file":"walk.png"}}}"#.utf8)),
        ("walk.png", Data("not an image".utf8)),
      ],
      to: zip
    )
    let library = makeLibrary()
    _ = await library.currentPack()
    let outcomes = await InstallOutcome.outcomes(for: [zip]) {
      try await library.install(zipAt: $0)
    } isCurrent: {
      library.isCurrent($0)
    } wearing: {
      await library.currentPack()?.descriptor.name
    }
    let replacement =
      hasReplacement
      ? "MonsterDeleter is using Kaiju instead." : "No other character could be loaded either."
    #expect(outcomes.count == 1)
    #expect(outcomes[0].isFailure)
    #expect(
      outcomes[0].message
        == "broken.zip: This character's artwork could not be read. \(replacement) Get a new copy and try Choose Zip in Settings."
    )
    #expect(library.currentEntry?.name == (hasReplacement ? "Kaiju" : nil))
  }

  @Test("failed reinstall reports the retained character independently of newly discovered metadata")
  func failedReinstallRetainsLoadedName() async throws {
    let zip = root.appending(path: "sea.zip")
    try TestZip.write([("pack.json", Data(#"{"name":"Sea"}"#.utf8))], to: zip)
    let library = makeLibrary()
    _ = try await library.install(zipAt: zip)
    try TestZip.write(
      [
        ("pack.json", Data(#"{"name":"New Sea","sheets":{"walk":{"file":"walk.png"}}}"#.utf8)),
        ("walk.png", Data("not an image".utf8)),
      ],
      to: zip
    )
    await #expect(throws: PackError.cannotDecode("walk.png")) {
      try await library.install(zipAt: zip)
    }
    #expect(library.entries.first { $0.id == "user/sea" }?.name == "New Sea")
    #expect(library.currentEntry?.name == "Sea")
    #expect(await library.currentPack()?.descriptor.name == "Sea")
    try addPack("bad", manifest: Self.brokenManifest)
    library.refresh()
    var report: LoadFailureQueue.Report?
    library.onLoadFailure = { entry, error in
      report = CharacterFailure.report(name: entry.name, error: error, wearing: library.currentEntry?.name)
    }
    library.select("user/bad")
    _ = await library.currentPack()
    #expect(report?.message.contains("MonsterDeleter is using Sea instead.") == true)
  }

  @Test("a rejected zip leaves the library as it was")
  func installRejected() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    let zip = root.appending(path: "art.zip")
    try TestZip.write([("walk.png", Data())], to: zip)
    let library = makeLibrary()
    await #expect(throws: PackInstallError.noManifest) { try await library.install(zipAt: zip) }
    #expect(library.entries.count == 1)
    #expect(library.currentID == "builtIn/kaiju")
  }

  @Test("each pack's sheets are cached in its own folder")
  func cachePerPack() async throws {
    try addPack("kaiju")
    try TestImages.writeSheet(to: packs.appending(path: "kaiju/kick.png"))
    let library = makeLibrary()
    library.select("user/kaiju")
    _ = await library.currentPack()
    let cached = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "cache/user/kaiju").path)
    #expect(cached.count == 1)
    #expect(cached[0].hasPrefix("kick-"))
  }

  @Test("choosing the loaded pack back while another is loading wins")
  func laterChoiceWins() async throws {
    try addBuiltInPack("kaiju", manifest: #"{"name": "Kaiju"}"#)
    try addPack("slow", manifest: #"{"name": "Slow"}"#)
    let library = makeLibrary()
    _ = await library.currentPack()
    library.select("user/slow")
    library.select("builtIn/kaiju")
    #expect(await library.currentPack()?.descriptor.name == "Kaiju")
    try await Task.sleep(for: .seconds(1))
    #expect(library.current?.descriptor.name == "Kaiju")
    #expect(library.currentID == "builtIn/kaiju")
  }
}
