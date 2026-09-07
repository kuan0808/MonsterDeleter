import Foundation

/// A zip file dropped on the settings window. Installing it lists the entries, refuses any that
/// would escape the pack folder, unpacks into a scratch folder with the system `unzip`, checks
/// that `pack.json` is there and names only files that exist, and only then moves the folder
/// into the user packs directory, replacing a pack of the same name.
public struct PackArchive: Sendable {
  /// What a character pack may unpack to. The archive's own listing is checked first, and
  /// because a zip may understate its sizes the scratch folder is measured again once `unzip`
  /// has run, so only an archive that fits both becomes a pack.
  public static let maximumUncompressedBytes = 512 * 1024 * 1024
  public static let maximumEntryCount = 1000

  public let url: URL
  let uncompressedBytesLimit: Int
  let entryCountLimit: Int

  public init(url: URL) {
    self.init(url: url, uncompressedBytesLimit: Self.maximumUncompressedBytes)
  }

  init(url: URL, uncompressedBytesLimit: Int, entryCountLimit: Int = PackArchive.maximumEntryCount) {
    self.url = url
    self.uncompressedBytesLimit = uncompressedBytesLimit
    self.entryCountLimit = entryCountLimit
  }

  /// The pack's folder name: the zip's name without its extension, reduced to letters, digits,
  /// dots, dashes and underscores; `pack` when nothing is left.
  public static func folderName(for fileName: String) -> String {
    var base = fileName.trimmingCharacters(in: .whitespaces)
    if base.lowercased().hasSuffix(".zip") {
      base = String(base.dropLast(4))
    }
    var name = ""
    for character in base {
      if character.isLetter || character.isNumber || character == "." || character == "_" || character == "-" {
        name.append(character)
      } else if !name.hasSuffix("-") {
        name.append("-")
      }
    }
    name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    return name.isEmpty ? "pack" : name
  }

  /// Installs the pack into `directory/<folder name>` and returns that folder.
  public func install(into directory: URL) throws -> URL {
    let names = try entryNames()
    for name in names {
      guard Self.isSafe(name) else { throw PackInstallError.unsafeEntry(name) }
    }
    try checkLimits(entryCount: names.count, uncompressedBytes: uncompressedBytes())
    let scratch = FileManager.default.temporaryDirectory.appending(path: "MonsterDeleter-install-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let unzip = try Self.run("/usr/bin/unzip", ["-q", "-o", "-d", scratch.path, url.path])
    guard unzip.status == 0 else { throw PackInstallError.extractionFailed(unzip.output) }
    let extracted = Self.extractedBytes(under: scratch)
    guard extracted <= uncompressedBytesLimit else { throw PackInstallError.archiveTooLarge(extracted) }
    try Self.rejectSymbolicLinks(under: scratch)
    let root = try Self.packRoot(in: scratch)
    try Self.validate(root)

    let destination = directory.appending(path: Self.folderName(for: url.lastPathComponent))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: root, to: destination)
    return destination
  }

  // MARK: Listing

  private func entryNames() throws -> [String] {
    let listing = try Self.run("/usr/bin/unzip", ["-Z1", url.path])
    guard listing.status == 0 else { throw PackInstallError.notAZip }
    return listing.output.split(separator: "\n").map(String.init)
  }

  /// The uncompressed size the archive's central directory declares, from `zipinfo`'s totals.
  func uncompressedBytes() throws -> Int {
    let totals = try Self.run("/usr/bin/unzip", ["-Z", "-t", url.path])
    guard totals.status == 0, let bytes = Self.uncompressedBytes(inTotals: totals.output) else {
      throw PackInstallError.notAZip
    }
    return bytes
  }

  static func uncompressedBytes(inTotals listing: String) -> Int? {
    guard let match = listing.firstMatch(of: /([0-9]+) bytes uncompressed/) else { return nil }
    return Int(match.1)
  }

  func checkLimits(entryCount: Int, uncompressedBytes: Int) throws {
    guard entryCount <= entryCountLimit else { throw PackInstallError.tooManyEntries(entryCount) }
    guard uncompressedBytes <= uncompressedBytesLimit else {
      throw PackInstallError.archiveTooLarge(uncompressedBytes)
    }
  }

  /// What the archive really unpacked to, whatever its headers declared.
  static func extractedBytes(under folder: URL) -> Int {
    let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
    guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
    var total = 0
    for case let file as URL in files {
      guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
        let size = values.fileSize
      else { continue }
      total += size
    }
    return total
  }

  /// Relative, with no `..` component and no absolute prefix.
  static func isSafe(_ name: String) -> Bool {
    guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\0") else { return false }
    return !name.split(separator: "/", omittingEmptySubsequences: false).contains("..")
  }

  // MARK: Validation

  private static func rejectSymbolicLinks(under folder: URL) throws {
    guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
    else { return }
    for case let file as URL in files
    where (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
      throw PackInstallError.unsafeEntry(file.lastPathComponent)
    }
  }

  /// The folder with `pack.json`: the archive root, or the single folder a Finder "Compress"
  /// wraps the pack in (its `__MACOSX` sidecar ignored).
  private static func packRoot(in scratch: URL) throws -> URL {
    if FileManager.default.fileExists(atPath: scratch.appending(path: "pack.json").path) {
      return scratch
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
      .filter { $0 != "__MACOSX" && !$0.hasPrefix(".") }
    guard names.count == 1 else { throw PackInstallError.noManifest }
    let inner = scratch.appending(path: names[0])
    guard FileManager.default.fileExists(atPath: inner.appending(path: "pack.json").path) else {
      throw PackInstallError.noManifest
    }
    return inner
  }

  private static func validate(_ root: URL) throws {
    guard let json = try? Data(contentsOf: root.appending(path: "pack.json")) else {
      throw PackInstallError.noManifest
    }
    guard let manifest = try? PackManifest(json: json) else { throw PackInstallError.invalidManifest }
    let sheets = manifest.declaredSheets.compactMap { manifest.descriptor.sheets[$0]?.file }
    let sounds = manifest.declaredAudio.compactMap { manifest.descriptor.audio[$0]?.file }
    for file in (sheets + sounds).sorted() {
      guard isSafe(file) else { throw PackInstallError.unsafeEntry(file) }
      guard FileManager.default.fileExists(atPath: root.appending(path: file).path) else {
        throw PackInstallError.missingFile(file)
      }
    }
  }

  // MARK: Process

  private static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      throw PackInstallError.extractionFailed(error.localizedDescription)
    }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: output, as: UTF8.self))
  }
}
