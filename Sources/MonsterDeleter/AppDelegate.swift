import AppKit
import MonsterDeleterKit
import os

/// AppKit bridge. Wires the Services provider, the target point monitor, the pack library and
/// the director together, and runs the `MONSTER_AUTOPLAY` show when asked.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// The characters and the chosen one.
  let library: PackLibrary
  /// How far the user has got: the introduction, the first Finder summon, the ring fallback.
  let onboarding = Onboarding()
  /// The preference and the Accessibility permission behind the show's icon aiming.
  let iconAiming: IconAiming
  /// Every time the app brings itself in front, so an activation of its own is never read as the
  /// user answering macOS's permission dialog.
  let activation: AppActivation
  /// The one switch that silences a show.
  let sound = ShowSound()

  /// The app window opens by itself until the introduction has been finished or skipped, so
  /// someone who has just installed the app meets it; never for a self-test or an export run. A
  /// Finder launch orders it in front; macOS 26 refuses an accessory app's own `activate()` at
  /// launch in observed runs, so the window is key once the
  /// user clicks it.
  var opensLandingWindow: Bool { launch.opensLandingWindow }

  private let logger = Logger(subsystem: "io.github.kuan0808.MonsterDeleter", category: "app")
  private let targetMonitor = TargetPointMonitor()
  private let failureNotice: TrashFailureNotice
  private let launch: LaunchDecision
  private var director: ShowDirector?
  private var selfTest: AutoplaySelfTest?
  private var loadFailures = LoadFailureQueue()

  override init() {
    let environment = ProcessInfo.processInfo.environment
    launch = LaunchDecision(
      environment: environment,
      hasCompletedOnboarding: UserDefaults.standard.bool(forKey: Onboarding.completedKey)
    )
    library = PackLibrary.standard(wearsStartingPack: !launch.isHeadless)
    let activation = AppActivation()
    self.activation = activation
    iconAiming = IconAiming(activation: activation)
    failureNotice = TrashFailureNotice(activation: activation)
    super.init()
    iconAiming.showIsRunning = { [weak self] in self?.director?.isRunning ?? false }
    library.onLoadFailure = { [weak self] entry, error in
      self?.reportLoadFailure(entry, error)
    }
  }

  /// Forwards focus loss to `IconAiming`, which also requires identifiable dialog-helper focus
  /// before waiting for an answer. Resignation alone is not proof of a permission dialog.
  func applicationWillResignActive(_ notification: Notification) {
    iconAiming.appResignedActive()
  }

  /// The focus is back, so that dialog has been answered - unless the app called it back itself.
  func applicationDidBecomeActive(_ notification: Notification) {
    iconAiming.appBecameActive()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let environment = ProcessInfo.processInfo.environment
    if let folder = environment["MONSTER_EXPORT_PLACEHOLDER"], !folder.isEmpty {
      exportPlaceholder(to: URL(fileURLWithPath: folder))
      return
    }
    targetMonitor.start()
    (NSApp.servicesProvider as? ServicesProvider)?.onSummon = { [weak self] urls in
      self?.summon(urls)
    }
    if let options = AutoplayOptions(environment: environment) {
      runAutoplay(options)
    }
  }

  /// The Finder Services item: the whole selection, aimed at the icons Finder draws for it when
  /// the accessibility tier can see them and at the last right-click otherwise.
  private func summon(_ urls: [URL]) {
    onboarding.recordSummonFromFinder()
    let sample = targetMonitor.lastSample
    let now = ContinuousClock.now
    let iconRects = iconAiming.iconRects
    let screens = NSScreen.screens.map(\.frame)
    Task { [weak self] in
      // The icons are read first, before a pack load can leave Finder time to move them.
      let started = ContinuousClock.now
      let aim = await TargetAimResolver.aim(
        for: urls,
        sample: sample,
        now: now,
        icons: iconRects,
        screens: screens
      )
      let took = started.duration(to: .now).components
      let milliseconds = took.seconds * 1000 + took.attoseconds / 1_000_000_000_000_000
      self?.logger.info(
        """
        Summoning \(urls.count, privacy: .public) target(s), \
        \(aim?.iconRects.count ?? 0, privacy: .public) icon(s) resolved \
        in \(milliseconds, privacy: .public) ms, \
        aiming at \(String(describing: aim?.point), privacy: .public)
        """
      )
      await self?.play(urls, aim: aim)
    }
  }

  /// Creates a scratch file and runs the show on it, aiming with the crosshair.
  func playDemo() {
    let name = "MonsterDeleter demo \(Int(Date.now.timeIntervalSince1970)).txt"
    let url = FileManager.default.temporaryDirectory.appending(path: name)
    do {
      try "Feed me to the monster.\n".write(to: url, atomically: true, encoding: .utf8)
    } catch {
      presentAlert(title: "Cannot create the demo file", message: error.localizedDescription)
      return
    }
    Task { await play([url], aim: nil) }
  }

  /// Runs one show in the chosen character, waiting for it to load first, so a summon right after
  /// a switch wears the new one. With no character that loads there is no show: the app says so
  /// and points at the Settings window rather than playing stand-in art.
  private func play(_ urls: [URL], aim: TargetAim?) async {
    guard let pack = await library.currentPack() else {
      presentAlert(
        title: "MonsterDeleter has no character to play",
        message: """
          None of the installed characters could be loaded, so there is no show to run. \
          Open Settings to add one.
          """
      )
      return
    }
    let director = director(wearing: pack)
    director.playsSound = sound.isEnabled
    director.summon(urls, aim: aim)
  }

  /// The one director, built when the first show needs it and dressed for every show after that.
  private func director(wearing pack: LoadedPack) -> ShowDirector {
    if let director {
      director.pack = pack
      return director
    }
    let director = ShowDirector(pack: pack, activation: activation)
    director.onFinished = { [weak self] phase, outcome, unaimedFan in
      self?.showFinished(phase, outcome: outcome, unaimedFan: unaimedFan)
    }
    director.onSwapRequested = { [weak self] in
      self?.swapPack()
    }
    director.canSwap = { [weak self] in self?.library.canSwap ?? false }
    self.director = director
    return director
  }

  /// A character that cannot be loaded is named, with its reason and what the app is wearing
  /// instead: never a silent fall back to stand-in art.
  private func reportLoadFailure(_ entry: PackEntry, _ error: any Error) {
    let report = CharacterFailure.report(name: entry.name, error: error, wearing: library.currentEntry?.name)
    present(loadFailures.enqueue(report, showIsRunning: director?.isRunning ?? false))
  }

  /// The swap button: choose the next character in the list and dress the running show in it.
  private func swapPack() {
    guard let next = library.entry(after: library.currentID ?? "") else { return }
    library.select(next.id)
    Task {
      guard let pack = await library.currentPack() else { return }
      director?.swap(to: pack)
    }
  }

  /// A selection of several whose icons could not be read explodes in a ring around the click,
  /// which reads as arbitrary unless the app says why; the app window offers aiming after such a
  /// show, and only after one that really happened.
  private func showFinished(_ phase: ShowPhase, outcome: TrashOutcome?, unaimedFan: UnaimedFan) {
    if unaimedFan.landedInARing(endingIn: phase) {
      onboarding.recordUnaimedFan()
    }
    present(loadFailures.drain())
    Task {
      if let outcome {
        await failureNotice.present(outcome)
      }
      if let selfTest, let status = selfTest.showEnded(phase, outcome: outcome) {
        exit(status)
      }
    }
  }

  /// The self-test: one show, judged by `AutoplaySelfTest`, then exit with its status.
  private func runAutoplay(_ options: AutoplayOptions) {
    // The self-test script reads the output while the show runs.
    setlinebuf(stdout)
    let point = options.point ?? NSScreen.main.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
    // Always the placeholder pack and no swap button, so the checkpoints match on every Mac.
    let placeholder: LoadedPack
    do {
      placeholder = try LoadedPack(source: PlaceholderPack())
    } catch {
      print("FAIL: the placeholder pack failed to load: \(error)")
      exit(1)
    }
    let director = director(wearing: placeholder)
    director.playsSound = true
    director.canSwap = { false }
    let selfTest = AutoplaySelfTest(options: options, point: point, director: director)
    self.selfTest = selfTest
    Task {
      if let id = options.packID {
        await wearPack(id, director: director)
      }
      try? await Task.sleep(for: .milliseconds(500))
      selfTest.summon()
    }
  }

  /// `MONSTER_AUTOPLAY_PACK`: the show wears that pack instead of the placeholder, so a pack can
  /// have its own evidence captured. An id the library does not hold ends the run rather than
  /// falling back, since the capture would then be of the wrong pack.
  private func wearPack(_ id: PackEntry.ID, director: ShowDirector) async {
    do {
      guard let pack = try await library.pack(for: id) else {
        print("FAIL: no pack with the id \(id)")
        exit(1)
      }
      director.pack = pack
    } catch {
      print("FAIL: the pack \(id) failed to load: \(error)")
      exit(1)
    }
  }

  /// `MONSTER_EXPORT_PLACEHOLDER=<folder>` writes the placeholder pack as files and quits: the
  /// template for authoring a character.
  private func exportPlaceholder(to folder: URL) {
    do {
      try PlaceholderPack().write(to: folder)
      print("exported placeholder pack to \(folder.path(percentEncoded: false))")
    } catch {
      print("export failed: \(error)")
    }
    NSApp.terminate(nil)
  }

  private func present(_ reports: [LoadFailureQueue.Report]) {
    for report in reports {
      presentAlert(title: report.title, message: report.message)
    }
  }

  private func presentAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    activation.activate()
    alert.runModal()
  }
}
