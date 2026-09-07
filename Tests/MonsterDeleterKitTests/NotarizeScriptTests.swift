import Foundation
import Testing

/// `scripts/notarize.sh` builds through `scripts/package.sh`, which writes a DMG when
/// `PACKAGE_DMG=1`. Only the zip that this path submits and staples may exist, so the script
/// forces `PACKAGE_DMG=0` whatever the environment says. The real script runs here against a
/// stub `scripts/package.sh` that records the value it was handed and then stops the run.
@Suite("Notarize script")
struct NotarizeScriptTests {
  @Test("it builds without a DMG even when the environment asks for one")
  func forcesNoDiskImage() throws {
    let manager = FileManager.default
    let sandbox = URL(filePath: NSTemporaryDirectory()).appending(path: "notarize-\(UUID().uuidString)")
    let scripts = sandbox.appending(path: "scripts")
    try manager.createDirectory(at: scripts, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: sandbox) }

    let script = scripts.appending(path: "notarize.sh")
    try manager.copyItem(at: AppBundleTests.root.appending(path: "scripts/notarize.sh"), to: script)
    let record = sandbox.appending(path: "package-dmg")
    let stub = scripts.appending(path: "package.sh")
    try """
    #!/bin/sh
    printf '%s' "${PACKAGE_DMG-unset}" > "\(record.path)"
    exit 1
    """.write(to: stub, atomically: true, encoding: .utf8)
    try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = [script.path]
    process.environment = [
      "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
      "PACKAGE_DMG": "1",
      "NOTARY_PROFILE": "test-profile",
      "CODESIGN_IDENTITY": "Developer ID Application: Test",
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()

    #expect(try String(contentsOf: record, encoding: .utf8) == "0")
  }
}
