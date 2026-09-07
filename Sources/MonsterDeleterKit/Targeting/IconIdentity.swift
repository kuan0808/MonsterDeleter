import Foundation

/// What one element of Finder's accessibility tree says about the file it stands for: the URL
/// Finder exposes for it, when it exposes one, and the name it displays.
///
/// This is the whole matching rule of the accessibility tier, kept apart from the tree walk so
/// it can be read and tested on its own. A target is never matched by where an element sits on
/// screen; a wrong match would send the monster to somebody else's file.
public struct IconIdentity: Sendable, Hashable {
  public var url: URL?
  public var name: String?

  public init(url: URL?, name: String?) {
    self.url = url
    self.name = name
  }

  /// The one key this element looks a target up by. A URL settles it in both directions: an
  /// element whose URL disagrees is not the target even when its name matches, which is what
  /// keeps two files of the same name in two Finder windows apart. Only an element without a URL
  /// falls back to the displayed name, which Finder writes with the extension hidden when the
  /// user asked for that. An element that says neither has no key and is never anybody's icon.
  public var lookupKey: String? {
    if let url { return Self.pathKey(url) }
    guard let name, !name.isEmpty else { return nil }
    return Self.nameKey(name)
  }

  /// Every target of one show, filed under each key an element can look it up by, so matching a
  /// selection costs one lookup per element rather than a scan of every target.
  ///
  /// A key two targets of the selection answer to is filed under neither of them: the folder
  /// `Report` and the file `Report.pdf` are both named "Report" once the extension is hidden, and
  /// an element showing that name alone could be either. An ambiguous element then resolves to
  /// nothing and its target falls to the right-click, which is the tier below, rather than
  /// borrowing the other file's icon. A URL is never ambiguous, so an element that carries one
  /// still resolves.
  public static func index(_ targets: [URL]) -> [String: URL] {
    var index: [String: URL] = [:]
    var ambiguous: Set<String> = []
    for target in targets {
      for key in keys(of: target) {
        guard let claimed = index[key] else {
          index[key] = target
          continue
        }
        if pathKey(claimed) != pathKey(target) {
          ambiguous.insert(key)
        }
      }
    }
    return index.filter { !ambiguous.contains($0.key) }
  }

  /// The keys one target answers to: its path, and the name Finder displays for it with the
  /// extension shown and with it hidden. A key carries what it is, so a name can never be read
  /// as a path.
  private static func keys(of target: URL) -> [String] {
    [
      pathKey(target),
      nameKey(target.lastPathComponent),
      nameKey(target.deletingPathExtension().lastPathComponent),
    ]
  }

  /// The comparable spelling of a file URL: standardized, and without the trailing slash Finder
  /// puts on a folder.
  private static func pathKey(_ url: URL) -> String {
    let path = url.standardizedFileURL.path(percentEncoded: false)
    guard path.count > 1, path.hasSuffix("/") else { return "path:\(path)" }
    return "path:\(path.dropLast())"
  }

  private static func nameKey(_ name: String) -> String { "name:\(name)" }
}
