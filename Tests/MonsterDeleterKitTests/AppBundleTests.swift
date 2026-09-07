import AppKit
import Foundation
import Testing

/// The packaging inputs (`Packaging/Info.plist`) and, when `scripts/build-app.sh` has run, the
/// assembled `build/MonsterDeleter.app`. The version lives in the plist alone; the build and
/// packaging scripts read it from there.
@Suite("App bundle")
struct AppBundleTests {
  /// The repo root: the nearest ancestor of this file that holds `Package.swift`.
  static let root: URL = {
    var url = URL(filePath: #filePath)
    while url.path != "/" {
      url = url.deletingLastPathComponent()
      if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
        return url
      }
    }
    return url
  }()
  static let packagingPlist = root.appending(path: "Packaging/Info.plist")
  static let app = root.appending(path: "build/MonsterDeleter.app")
  static var appIsBuilt: Bool { FileManager.default.fileExists(atPath: app.path) }

  @Test("the version is a semantic version with an integer build number")
  func version() throws {
    let info = try plist(Self.packagingPlist)
    let version = try #require(info["CFBundleShortVersionString"] as? String)
    #expect(version.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil, "\(version)")
    let build = try #require(info["CFBundleVersion"] as? String)
    #expect(Int(build) != nil, "\(build)")
  }

  @Test("the plist names the icon file and keeps the Services port on the executable")
  func iconAndPort() throws {
    let info = try plist(Self.packagingPlist)
    #expect(info["CFBundleIconFile"] as? String == "AppIcon")
    let services = try #require(info["NSServices"] as? [[String: Any]])
    let port = try #require(services.first?["NSPortName"] as? String)
    #expect(port == info["CFBundleExecutable"] as? String)
  }

  @Test("the built bundle carries the icon at every size", .enabled(if: appIsBuilt))
  func builtIcon() throws {
    let icon = try #require(NSImage(contentsOf: Self.app.appending(path: "Contents/Resources/AppIcon.icns")))
    let widths = Set(icon.representations.map(\.pixelsWide))
    #expect(widths.isSuperset(of: [16, 32, 128, 256, 512, 1024]), "\(widths.sorted())")
  }

  @Test("the built bundle's Info.plist is the packaging one", .enabled(if: appIsBuilt))
  func builtPlist() throws {
    let built = try plist(Self.app.appending(path: "Contents/Info.plist"))
    let source = try plist(Self.packagingPlist)
    #expect(NSDictionary(dictionary: built) == NSDictionary(dictionary: source))
  }

  @Test("the built bundle has a built-in packs folder", .enabled(if: appIsBuilt))
  func builtPacksFolder() {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: Self.app.appending(path: "Contents/Resources/packs").path,
      isDirectory: &isDirectory
    )
    #expect(exists && isDirectory.boolValue)
  }

  /// The menu bar image ships at both scales under the name that makes AppKit tint it, which is
  /// the name `MenuBarIcon` asks the bundle for.
  @Test("the built bundle carries the menu bar template at 18 points and 2x", .enabled(if: appIsBuilt))
  func builtMenuBarTemplate() throws {
    for (name, side) in [("MenuBarIconTemplate.png", 18), ("MenuBarIconTemplate@2x.png", 36)] {
      let url = Self.app.appending(path: "Contents/Resources/\(name)")
      let image = try #require(NSImage(contentsOf: url), "\(name) is missing from the bundle")
      let pixels = try #require(image.representations.first)
      #expect(pixels.pixelsWide == side && pixels.pixelsHigh == side, "\(name) is \(pixels.pixelsWide) px")
    }
  }

  @Test("the parsed package and plist deploy to macOS 15")
  func deploymentTarget() throws {
    let scratch = Self.root.appending(path: "build/package-inspection-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = [
      "swift", "package", "--scratch-path", scratch.path, "--package-path", Self.root.path, "dump-package",
    ]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let package = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let platforms = try #require(package["platforms"] as? [[String: Any]])
    let macOS = try #require(platforms.first { $0["platformName"] as? String == "macos" })
    #expect(macOS["version"] as? String == "15.0")
    #expect(try plist(Self.packagingPlist)["LSMinimumSystemVersion"] as? String == "15.0")
  }

  @Test("the signed bundle contains both macOS 15 executable slices", .enabled(if: appIsBuilt))
  func executableSlices() throws {
    let process = Process()
    process.executableURL = Self.root.appending(path: "scripts/check-app.sh")
    process.arguments = [Self.app.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
  }

  private func plist(_ url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  }
}
