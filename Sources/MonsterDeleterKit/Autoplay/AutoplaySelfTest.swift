import AppKit
import ApplicationServices
import QuartzCore

/// AppKit bridge. Drives one `MONSTER_AUTOPLAY` show through the director and judges it: every
/// event against the choreography's timetable, the selection in the Trash (or untouched after
/// an Esc), and each checkpoint capture against its reference. Prints one line per event and
/// per finding, and hands back the exit status. A show that never ends fails the watchdog.
@MainActor
public final class AutoplaySelfTest {
  /// How far a transition may sit from the table. The render server keeps the show within a few
  /// milliseconds; a loaded CI runner gets the rest.
  public static let tolerance = Duration.milliseconds(150)
  /// The share of a checkpoint's pixels that may differ from its reference: a pixel or two of
  /// motion jitter on the walk and text antialiasing, not a missing sprite (three percent or
  /// more of the capture) or a missing bubble.
  public static let snapshotTolerance = 0.02
  public static let timeout = Duration.seconds(60)

  private let options: AutoplayOptions
  private let point: CGPoint?
  private let director: ShowDirector
  private var trace = ShowTrace()
  private var captures: [ShowCheckpoint: CGImage] = [:]
  private var problems: [String] = []
  private var tasks: [Task<Void, Never>] = []
  private var watchdog: Task<Void, Never>?
  private var showsPlayed = 0
  private var checkpointsCaptured = 0
  /// Which targets are folders, so a later show can recreate them.
  private var folderTargets: Set<URL> = []

  public init(options: AutoplayOptions, point: CGPoint?, director: ShowDirector) {
    self.options = options
    self.point = point
    self.director = director
  }

  /// Starts the first show on the director's current pack. The director's event hook is taken
  /// over.
  public func summon() {
    #if arch(arm64)
      print("autoplay executable slice arm64")
    #elseif arch(x86_64)
      print("autoplay executable slice x86_64")
    #endif
    logInteraction("summon")
    let paths = options.targets.map { $0.path(percentEncoded: false) }.joined(separator: " ")
    print("autoplay start \(paths) at \(point.map { "\($0)" } ?? "aiming")")
    print("autoplay pack \(director.pack.descriptor.name)")
    let scale = Self.backingScale(around: point)
    print("autoplay screen scale \(scale)x")
    if scale != 1 {
      print(
        "skip: the references are 1x captures, so the checkpoint comparison is only reliable on a 1x screen; this one is \(scale)x and the bubble and button glyph edges may differ"
      )
    }
    print("autoplay answer \(options.answer.rawValue) after \(ShowTrace.seconds(options.confirmDelay))")
    if options.shows > 1 {
      print("autoplay shows \(options.shows)")
    }
    for target in options.targets {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: target.path(percentEncoded: false), isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        folderTargets.insert(target)
      }
    }
    director.onEvent = { [weak self] event, elapsed in
      self?.record(event, at: elapsed)
    }
    play()
  }

  /// Judges the show that just ended and, when another is due, starts it half a second later;
  /// otherwise prints the verdict and hands back the exit status. `phase` is `nil` when the
  /// watchdog fired.
  public func showEnded(_ phase: ShowPhase?, outcome: TrashOutcome?) -> Int32? {
    watchdog?.cancel()
    for task in tasks {
      task.cancel()
    }
    tasks.removeAll()
    showsPlayed += 1
    if let phase {
      print(
        "finished \(phase.rawValue) trashed=\(outcome?.trashed.count ?? 0) failures=\(outcome?.failures.count ?? 0)"
      )
    }
    let choreography = director.pack.choreography
    let timetable =
      switch options.answer {
      case .confirm: ShowTimetable.confirmed(choreography, confirmDelay: options.confirmDelay)
      case .escape: ShowTimetable.cancelled(choreography, cancelDelay: options.confirmDelay)
      }
    problems += trace.problems(against: timetable, tolerance: Self.tolerance)
    checkTrash(outcome)
    checkSnapshots()
    checkpointsCaptured += captures.count
    if let footprint = Self.footprint {
      print(
        "memory after show \(showsPlayed): \(footprint.formatted(.byteCount(style: .memory).locale(ShowTrace.logLocale)))"
      )
    }
    if phase != nil, showsPlayed < options.shows {
      trace = ShowTrace()
      captures.removeAll()
      recreateTargets()
      tasks.append(
        Task { [weak self] in
          try? await Task.sleep(for: .milliseconds(500))
          guard !Task.isCancelled else { return }
          self?.play()
        }
      )
      return nil
    }
    for problem in problems {
      print("FAIL: \(problem)")
    }
    let shows = "\(showsPlayed) show\(showsPlayed == 1 ? "" : "s")"
    if problems.isEmpty {
      print("self-test passed: \(shows), \(checkpointsCaptured) checkpoints")
      return 0
    }
    print("self-test failed: \(problems.count) problem\(problems.count == 1 ? "" : "s") in \(shows)")
    return 1
  }

  private func play() {
    if options.shows > 1 {
      print("== show \(showsPlayed + 1) of \(options.shows)")
    }
    watchdog = Task { [weak self] in
      try? await Task.sleep(for: Self.timeout)
      guard !Task.isCancelled, let self else { return }
      print("FAIL: the show did not finish within \(ShowTrace.seconds(Self.timeout))")
      _ = self.showEnded(nil, outcome: nil)
      exit(2)
    }
    director.summon(options.targets, aim: point.map { TargetAim(point: $0) })
  }

  /// Puts back the scratch items a confirmed show trashed, so the next show has its selection.
  private func recreateTargets() {
    let fileManager = FileManager.default
    for target in options.targets where !fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
      do {
        if folderTargets.contains(target) {
          try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        } else {
          try "Feed me to the monster.\n".write(to: target, atomically: true, encoding: .utf8)
        }
      } catch {
        problems.append("cannot recreate \(target.path(percentEncoded: false)): \(error.localizedDescription)")
      }
    }
  }

  /// The backing scale of the screen the show plays on. The references are captured at 1x, and
  /// a Retina screen caches the hosted SwiftUI layers at its own scale and downsamples them into
  /// the 1x capture, which moves the glyph edges of the bubble and the buttons.
  private static func backingScale(around point: CGPoint?) -> CGFloat {
    let screen = point.flatMap { target in NSScreen.screens.first { $0.frame.contains(target) } } ?? NSScreen.main
    return screen?.backingScaleFactor ?? 1
  }

  /// The process's physical footprint, the number Activity Monitor calls Memory.
  private static var footprint: Int? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return Int(info.phys_footprint)
  }

  // MARK: Events

  private func record(_ event: ShowEvent, at elapsed: Duration) {
    print("event \(ShowTrace.name(event)) at \(ShowTrace.seconds(elapsed))")
    trace.record(event, at: elapsed)
    switch event {
    case .entered(let phase):
      if phase == .asking || phase == .cancelled { logInteraction(phase.rawValue) }
      scheduleCheckpoints(of: phase)
    case .askBubbleDue:
      scheduleAnswer()
    }
  }

  private func scheduleCheckpoints(of phase: ShowPhase) {
    guard options.snapshotDirectory != nil || options.referenceDirectory != nil else { return }
    let choreography = director.pack.choreography
    for checkpoint in ShowCheckpoint.allCases where checkpoint.phase == phase {
      let due = ContinuousClock.now + checkpoint.offset(in: choreography)
      tasks.append(
        Task { [weak self] in
          try? await ContinuousClock().sleep(until: due, tolerance: .milliseconds(2))
          guard !Task.isCancelled else { return }
          await self?.capture(checkpoint)
        }
      )
    }
  }

  private func scheduleAnswer() {
    tasks.append(
      Task { [weak self] in
        try? await Task.sleep(for: self?.options.confirmDelay ?? .zero)
        guard !Task.isCancelled else { return }
        self?.answer()
      }
    )
  }

  private func answer() {
    logInteraction("answer \(options.answer.rawValue)")
    switch options.answer {
    case .confirm:
      print("autoplay confirm")
      director.confirm()
    case .escape:
      pressEscape()
    }
  }

  /// Esc the way a user presses it when the app is active and may post keyboard events
  /// (Accessibility), and straight to the app otherwise. The overlay panel must be key for a
  /// real Esc to reach it, which can only be checked while the app is active: macOS lets an app
  /// activate itself only when the user launched it, and never at the lock screen, so a launch
  /// from a shell may stay inactive. A keystroke is never posted while another app is frontmost.
  private func pressEscape() {
    if NSApp.isActive {
      if !(NSApp.keyWindow is OverlayPanel) {
        problems.append("the overlay panel is not the key window during the ask, so Esc would go to another app")
      }
      if AXIsProcessTrusted() {
        print("autoplay esc through a keyboard event (the app is active and Accessibility is granted)")
        for down in [true, false] {
          let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)
          // Tag only our synthetic Esc, so an unrelated input cannot be mistaken for it.
          event?.setIntegerValueField(.eventSourceUserData, value: Int64(ProcessInfo.processInfo.processIdentifier))
          event?.post(tap: .cghidEventTap)
        }
        logInteraction("posted Esc")
        return
      }
      print("skip: a keyboard Esc needs Accessibility for MonsterDeleter; sending Esc to the key window instead")
    } else {
      let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
      print(
        "skip: MonsterDeleter is not the active app (frontmost: \(frontmost)), so the keyboard-focus check and a keyboard Esc need a user launch in an unlocked session; sending Esc to the overlay panel instead"
      )
    }
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: NSApp.keyWindow?.windowNumber ?? 0,
        context: nil,
        characters: "\u{1B}",
        charactersIgnoringModifiers: "\u{1B}",
        isARepeat: false,
        keyCode: 53
      )
    else {
      problems.append("could not make the Esc key event")
      return
    }
    print("autoplay esc")
    NSApp.sendEvent(event)
  }

  /// Self-test diagnostics only. Uptime and the event's own timestamp separate a late answer
  /// task from delayed input delivery; source PID and our Esc tag identify received input.
  /// `currentEvent` may be stale, so it is evidence of the current event, not proof of causation.
  private func logInteraction(_ action: String) {
    let process = ProcessInfo.processInfo
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    let key = NSApp.keyWindow?.windowNumber ?? 0
    print(
      "input \(action) uptime=\(process.systemUptime) pid=\(process.processIdentifier) active=\(NSApp.isActive) frontPID=\(front) keyWindow=\(key)"
    )
    if let event = NSApp.currentEvent {
      let source = event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? -1
      let tag = event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0
      print(
        "current event type=\(event.type.rawValue) timestamp=\(event.timestamp) sourcePID=\(source) tag=\(tag)"
      )
    }
  }

  // MARK: Checkpoints

  /// Draws the checkpoint's own moment of the show, whenever this task reaches it: a loaded
  /// machine can wake it a frame slot late, and drawing what is on screen by then would catch
  /// the next sprite frame. A task that arrives early waits for the moment instead.
  private func capture(_ checkpoint: ShowCheckpoint) async {
    guard let target = director.target else {
      problems.append("no target point to capture \(checkpoint.fileName) around")
      return
    }
    guard director.phase == checkpoint.phase else {
      problems.append(
        "\(checkpoint.fileName) came due in \(director.phase?.rawValue ?? "no phase"), not \(checkpoint.phase.rawValue)"
      )
      return
    }
    guard let animationStart = director.animationStart(of: checkpoint.phase) else {
      problems.append("\(checkpoint.fileName) has no \(checkpoint.phase.rawValue) frames to follow")
      return
    }
    let moment = CheckpointCapture(
      checkpoint,
      animationStart: animationStart,
      now: CACurrentMediaTime(),
      choreography: director.pack.choreography
    )
    if moment.waits > .zero {
      try? await Task.sleep(for: moment.waits)
      guard !Task.isCancelled else { return }
    }
    guard let image = director.snapshot(of: ShowCheckpoint.captureRect(around: target), at: moment.showTime) else {
      problems.append("no overlay to capture for \(checkpoint.fileName)")
      return
    }
    captures[checkpoint] = image
    print("checkpoint \(checkpoint.fileName) captured")
    guard let folder = options.snapshotDirectory else { return }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try PNGFile.write(image, to: folder.appending(path: checkpoint.fileName))
    } catch {
      problems.append("cannot write \(checkpoint.fileName): \(error.localizedDescription)")
    }
  }

  private func checkSnapshots() {
    guard let reference = options.referenceDirectory else { return }
    for checkpoint in ShowCheckpoint.allCases {
      guard let capture = captures[checkpoint] else {
        problems.append("\(checkpoint.fileName) was never captured")
        continue
      }
      guard let expected = PNGFile.read(reference.appending(path: checkpoint.fileName)) else {
        problems.append("no reference \(checkpoint.fileName) in \(reference.path(percentEncoded: false))")
        continue
      }
      guard capture.width == expected.width, capture.height == expected.height else {
        problems.append(
          "\(checkpoint.fileName) is \(capture.width) x \(capture.height), the reference \(expected.width) x \(expected.height)"
        )
        continue
      }
      guard let mismatch = SnapshotComparison.mismatch(capture, expected) else {
        problems.append("\(checkpoint.fileName) and its reference could not be read as pixels")
        continue
      }
      let percent = (mismatch * 100).formatted(.number.precision(.fractionLength(2)).locale(ShowTrace.logLocale))
      print("checkpoint \(checkpoint.fileName) differs from its reference by \(percent)%")
      if mismatch > Self.snapshotTolerance {
        problems.append("\(checkpoint.fileName) differs from its reference by \(percent)%, more than the allowed 2%")
      }
    }
  }

  // MARK: Trash

  private func checkTrash(_ outcome: TrashOutcome?) {
    let fileManager = FileManager.default
    switch options.answer {
    case .confirm:
      guard let outcome else {
        problems.append("the show ended without a trash outcome")
        return
      }
      for failure in outcome.failures {
        problems.append("\(failure.url.path(percentEncoded: false)) was not trashed: \(failure.message)")
      }
      for target in options.targets {
        let path = target.path(percentEncoded: false)
        if fileManager.fileExists(atPath: path) {
          problems.append("\(path) is still there")
        }
        guard let trashed = outcome.trashed[target] else {
          if !outcome.failures.contains(where: { $0.url == target }) {
            problems.append("\(path) is missing from the outcome")
          }
          continue
        }
        if fileManager.fileExists(atPath: trashed.path(percentEncoded: false)) {
          print("trashed \(path) as \(trashed.path(percentEncoded: false))")
        } else {
          problems.append("\(path) did not land in the Trash at \(trashed.path(percentEncoded: false))")
        }
      }
    case .escape:
      if outcome != nil {
        problems.append("a cancelled show still produced a trash outcome")
      }
      for target in options.targets {
        let path = target.path(percentEncoded: false)
        if fileManager.fileExists(atPath: path) {
          print("untouched \(path)")
        } else {
          problems.append("\(path) is gone although the show was cancelled")
        }
      }
    }
  }
}
