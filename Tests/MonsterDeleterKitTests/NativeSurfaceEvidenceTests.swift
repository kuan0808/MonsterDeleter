import AppKit
import SwiftUI
import Testing

@testable import MonsterDeleterKit

/// Opt-in native renders. Permission signals are supplied at the existing system seam;
/// these images establish layout and keyboard interaction, not that macOS displayed its dialog.
/// Build with `scripts/build-app.sh debug`, then set MONSTER_SURFACE_EVIDENCE to an existing
/// evidence directory and run `swift test --filter NativeSurfaceEvidenceTests`. Screen Recording
/// must be granted to the launching terminal. Run this suite alone: it owns an AppKit window.
@MainActor
@Suite("Native first-run evidence", .serialized)
struct NativeSurfaceEvidenceTests {
  /// Renders the changed guidance without taking desktop focus or needing Screen Recording.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MONSTER_SURFACE_EVIDENCE"] != nil))
  func trashGuidanceOffscreen() throws {
    let output = URL(filePath: try #require(ProcessInfo.processInfo.environment["MONSTER_SURFACE_EVIDENCE"]))
    _ = NSApplication.shared
    NSApp.applicationIconImage = NSImage(
      contentsOf: AppBundleTests.root.appending(path: "Packaging/Icon/AppIcon-1024.png")
    )

    func capture(_ name: String, content: some View) throws {
      let host = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
      host.appearance = NSAppearance(named: .aqua)
      host.setFrameSize(host.fittingSize)
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try #require(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: output.appending(path: "\(name).png"))
      #expect(host.bounds.width == 460)
    }

    try capture("guide-trash-guidance", content: GuideView(dismiss: {}))
    let introduction = OnboardingLayoutTests().introduction()
    try capture(
      "onboarding-trash-guidance",
      content: introduction.whatItDoes.frame(width: OnboardingView.stepWidth).padding(24)
    )
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["MONSTER_SURFACE_EVIDENCE"] != nil))
  func firstRunSurfaces() async throws {
    let output = URL(filePath: try #require(ProcessInfo.processInfo.environment["MONSTER_SURFACE_EVIDENCE"]))
    let root = URL(filePath: FileManager.default.currentDirectoryPath)
    let scratch = root.appending(path: ".build/native-surface-evidence")
    let suite = "NativeSurfaceEvidenceTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: scratch)
    }
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.applicationIconImage = NSImage(contentsOf: root.appending(path: "Packaging/Icon/AppIcon-1024.png"))
    let library = PackLibrary(
      userPacksDirectory: scratch.appending(path: "packs"),
      cacheDirectory: scratch.appending(path: "cache"),
      builtInPacksDirectory: root.appending(path: "build/MonsterDeleter.app/Contents/Resources/packs"),
      defaults: defaults
    )
    #expect(await library.currentPack()?.descriptor.name == "Kaiju")
    #expect(defaults.string(forKey: PackLibrary.selectionKey) == nil)
    let calls = IconAimingTests.SystemCalls()
    calls.isAppActive = true
    let aiming = IconAiming(
      defaults: defaults,
      prompt: { false },
      trusted: { calls.isTrusted },
      openURL: { _ in },
      isAppActive: { calls.isAppActive },
      promptOwnsFocus: { calls.promptOwnsFocus }
    )
    let onboarding = Onboarding(defaults: defaults)
    onboarding.complete()
    let host = NSHostingView(
      rootView: LandingView(
        library: library,
        onboarding: onboarding,
        iconAiming: aiming,
        playDemo: {}
      )
    )
    let window = NSWindow(
      contentRect: CGRect(x: 80, y: 80, width: 460, height: 403),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    let originalFrame = window.frame

    func capture(_ name: String, view: NSView = host) async throws {
      try await Task.sleep(for: .milliseconds(350))
      view.layoutSubtreeIfNeeded()
      let command = Process()
      command.executableURL = URL(filePath: "/usr/sbin/screencapture")
      command.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appending(path: "\(name).png").path]
      try command.run()
      command.waitUntilExit()
      #expect(command.terminationStatus == 0)
    }
    func pressReturn() throws {
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown,
          location: .zero,
          modifierFlags: [],
          timestamp: 0,
          windowNumber: window.windowNumber,
          context: nil,
          characters: "\r",
          charactersIgnoringModifiers: "\r",
          isARepeat: false,
          keyCode: 36
        )
      )
      window.sendEvent(event)
    }

    try await capture("home-before-introduction")
    onboarding.restart()
    try await capture("home-to-introduction")
    #expect(!onboarding.isCompleted)
    #expect(window.frame == originalFrame)
    try pressReturn()
    try await capture("onboarding-finder")
    try pressReturn()
    try await capture("onboarding-never-asked")
    try pressReturn()
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    #expect(aiming.isWaitingForAnswer)
    try await capture("onboarding-waiting-simulated")
    aiming.appBecameActive()
    #expect(aiming.needsPermission)
    try await capture("onboarding-missing-simulated")
    calls.isTrusted = true
    aiming.appBecameActive()
    #expect(aiming.isActive)
    try await capture("onboarding-granted-simulated")
    try pressReturn()
    try await capture("home-before-tip")
    calls.isTrusted = false
    aiming.appBecameActive()
    onboarding.recordUnaimedFan()
    try await capture("home-to-tip-simulated-completion")
    #expect(window.frame == originalFrame)
    print("Landing window kept \(originalFrame) across introduction and aiming offer")
    onboarding.dismissAimingTip()
    #expect(!onboarding.sawUnaimedFan)

    let settings = NSHostingView(
      rootView: SettingsView(
        library: library,
        iconAiming: aiming,
        sound: ShowSound(defaults: defaults)
      )
    )
    window.contentView = settings
    window.setContentSize(settings.fittingSize)
    try await Task.sleep(for: .seconds(2))
    try await capture("settings-missing-simulated", view: settings)
    calls.promptOwnsFocus = false
    aiming.setEnabled(true)
    calls.promptOwnsFocus = true
    aiming.appResignedActive()
    #expect(aiming.isWaitingForAnswer)
    try await capture("settings-waiting-simulated", view: settings)
    calls.isTrusted = true
    aiming.appBecameActive()
    try await capture("settings-granted-simulated", view: settings)
    aiming.setEnabled(false)
    try await capture("settings-off", view: settings)
    window.appearance = NSAppearance(named: .aqua)
    try await capture("settings-off-light", view: settings)
  }
}
