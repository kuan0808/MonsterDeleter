// swift-tools-version: 6.2
import PackageDescription

// Swift 6 language mode already checks concurrency completely; the explicit flag keeps the
// repo convention visible in one place.
let strictConcurrency: [SwiftSetting] = [
  .unsafeFlags(["-strict-concurrency=complete"])
]

let package = Package(
  name: "MonsterDeleter",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "MonsterDeleter", targets: ["MonsterDeleter"]),
    .library(name: "MonsterDeleterKit", targets: ["MonsterDeleterKit"]),
  ],
  targets: [
    .target(
      name: "MonsterDeleterKit",
      swiftSettings: strictConcurrency
    ),
    .executableTarget(
      name: "MonsterDeleter",
      dependencies: ["MonsterDeleterKit"],
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "MonsterDeleterKitTests",
      dependencies: ["MonsterDeleterKit"],
      swiftSettings: strictConcurrency
    ),
  ],
  swiftLanguageModes: [.v6]
)
