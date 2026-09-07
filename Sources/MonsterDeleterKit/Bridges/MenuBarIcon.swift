import AppKit

/// AppKit bridge. The menu bar image, loaded from the app bundle's resources.
///
/// The bundle has no asset catalog by design (`docs/adr/0001-swiftpm-app-bundle.md`), so SwiftUI's
/// `Image("name")` finds nothing and `MenuBarExtra` would show an empty item; `NSImage(named:)`
/// does search the bundle's resources. The name ends in "Template", which is how AppKit is told to
/// tint the silhouette itself, so it is right in a light bar, a dark bar and one tinted by the
/// wallpaper. A build without the resource falls back to a system symbol rather than to nothing.
public enum MenuBarIcon {
  public static let resourceName = "MenuBarIconTemplate"

  @MainActor
  public static let image: NSImage = {
    if let named = NSImage(named: resourceName) {
      named.isTemplate = true
      return named
    }
    let fallback = NSImage(systemSymbolName: "ladybug.fill", accessibilityDescription: "MonsterDeleter")
    return fallback ?? NSImage(size: NSSize(width: 18, height: 18))
  }()
}
