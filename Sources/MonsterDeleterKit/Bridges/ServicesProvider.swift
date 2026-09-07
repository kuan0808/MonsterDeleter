import AppKit

/// AppKit bridge. The object `pbs` calls for the Finder Services item declared in Info.plist
/// (`NSMessage summonMonster`). SwiftUI has no Services API. Installed on `NSApp.servicesProvider`
/// before the run loop starts so a cold launch by pbs finds it (spike decision 1).
@MainActor
public final class ServicesProvider: NSObject {
  /// The whole selection, files and folders, sorted; one show for all of it.
  public var onSummon: (([URL]) -> Void)?

  @objc public func summonMonster(
    _ pasteboard: NSPasteboard,
    userData: String,
    error: AutoreleasingUnsafeMutablePointer<NSString>
  ) {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty
    else {
      error.pointee = "MonsterDeleter needs at least one file or folder."
      return
    }
    onSummon?(SelectionOrder.sorted(urls))
  }
}
