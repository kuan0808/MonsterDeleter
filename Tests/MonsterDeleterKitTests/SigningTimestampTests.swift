import Foundation
import Testing

/// `scripts/lib/signing.sh` decides the `codesign` timestamp flag for an identity, which
/// `scripts/build-app.sh` reads. Only a Developer ID build reaches Apple's timestamp authority;
/// an ad hoc or personal-team build signs offline.
@Suite("Signing timestamp")
struct SigningTimestampTests {
  @Test(
    "it asks for a secure timestamp only with a Developer ID identity",
    arguments: [
      ("-", "--timestamp=none"),
      ("Apple Development: Captain (TEAMID)", "--timestamp=none"),
      ("Developer ID Application: Captain (TEAMID)", "--timestamp"),
    ]
  )
  func timestampFlag(identity: String, flag: String) throws {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = [AppBundleTests.root.appending(path: "scripts/lib/signing.sh").path, identity]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = try output.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
    #expect(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines) == flag)
  }
}
