import AppKit
import os

/// AppKit bridge. Runs one show: owns the machine, turns its events into stage, audio and trash
/// effects, and schedules ticks on the continuous clock. A SwiftUI scene cannot own this: the
/// show lives in AppKit overlay panels driven by Core Animation, outside any SwiftUI view's
/// lifetime, and starts from a Services message rather than a view event. One show at a time; a
/// second summon is ignored.
@MainActor
public final class ShowDirector {
  /// Every machine event with the time since the show started, for logs and autoplay.
  public var onEvent: ((ShowEvent, Duration) -> Void)?
  /// The show ended, with the trash outcome when the kick happened.
  public var onFinished: ((ShowPhase, TrashOutcome?, UnaimedFan) -> Void)?
  /// The swap button was pressed; whoever owns the pack library answers with `swap(to:)`.
  /// Without a handler the bubble has no swap button.
  public var onSwapRequested: (() -> Void)?
  /// Whether there is another pack to swap to. Asked every time the bubble is shown, so a pack
  /// installed mid-session counts; without it the bubble has no swap button.
  public var canSwap: (() -> Bool)?

  /// The pack the next summon dresses the show in.
  public var pack: LoadedPack
  /// Whether the show may play its pack's sounds; the user's one mute switch (`ShowSound`).
  /// Read at each summon and swap, so turning it off applies to the next show, not this one.
  public var playsSound = true
  private let activation: AppActivation
  private let trash: @MainActor ([URL]) async -> TrashOutcome
  private let clock = ContinuousClock()
  private let logger = Logger(subsystem: "io.github.kuan0808.MonsterDeleter", category: "show")
  private var machine: ShowMachine<ContinuousClock>?
  private var stage: ShowStage?
  private var audio: AudioPlayer?
  private var layout: ShowLayout?
  /// Where this show aims, kept beside the machine: the machine owns the target point and the
  /// phase, this owns the icons the accessibility tier resolved for it.
  private var aim: TargetAim?
  private var targetURLs: [URL] = []
  private var startedAt: ContinuousClock.Instant?
  private var tickTask: Task<Void, Never>?
  private var trashTask: Task<TrashOutcome, Never>?
  private var previousApp: NSRunningApplication?

  public init(
    pack: LoadedPack,
    activation: AppActivation = AppActivation(),
    trash: @escaping @MainActor ([URL]) async -> TrashOutcome = { await TrashService.trash($0) }
  ) {
    self.pack = pack
    self.activation = activation
    self.trash = trash
  }

  public var isRunning: Bool {
    guard let machine else { return false }
    return !machine.phase.isTerminal
  }

  public var phase: ShowPhase? { machine?.phase }

  /// The running show's target point, once known.
  public var target: CGPoint? { machine?.target }

  /// The overlay as drawn at `showTime` inside `rect`, for the self-test's checkpoints.
  public func snapshot(of rect: CGRect, at showTime: CFTimeInterval) -> CGImage? {
    stage?.snapshot(of: rect, at: showTime)
  }

  /// When the frames `phase` plays started, on Core Animation's clock, for those captures.
  public func animationStart(of phase: ShowPhase) -> CFTimeInterval? {
    stage?.animationStart(of: phase)
  }

  /// Starts one show for the whole selection, already sorted. With an `aim` the monster walks
  /// straight in; without one the crosshair comes up first.
  public func summon(_ urls: [URL], aim: TargetAim?) {
    guard !urls.isEmpty else {
      logger.notice("Ignoring summon with an empty selection")
      return
    }
    guard !isRunning else {
      logger.notice("Ignoring summon while a show is running")
      return
    }
    targetURLs = urls
    self.aim = aim
    layout = nil
    trashTask = nil
    previousApp = nil
    let stage = ShowStage(pack: pack)
    stage.onClick = { [weak self] point in self?.click(at: point) }
    stage.onCancel = { [weak self] in self?.cancel() }
    self.stage = stage
    audio = playsSound ? AudioPlayer(pack: pack) : nil
    startedAt = clock.now
    var machine = ShowMachine(
      choreography: pack.choreography,
      clock: clock,
      target: aim?.point,
      targetCount: urls.count
    )
    let events = machine.start()
    self.machine = machine
    apply(events)
  }

  public func confirm() {
    guard var machine else { return }
    let events = machine.confirm()
    self.machine = machine
    apply(events)
  }

  public func cancel() {
    guard var machine else { return }
    let events = machine.cancel()
    self.machine = machine
    apply(events)
  }

  /// Dresses the running show in `newPack` while the monster is asking. The machine and its
  /// timing are untouched; the frames, sounds, bubble and buttons change.
  public func swap(to newPack: LoadedPack) {
    guard let machine, machine.phase == .asking, let aim, let stage else { return }
    logger.info("Swapping to pack \(newPack.descriptor.name, privacy: .public)")
    pack = newPack
    audio?.stopAll()
    audio = playsSound ? AudioPlayer(pack: newPack) : nil
    audio?.play(.bgm)
    guard let layout = stage.swap(to: newPack, aim: aim, targetCount: machine.targetCount) else { return }
    self.layout = layout
    showBubble()
  }

  private func click(at point: CGPoint) {
    guard var machine else { return }
    switch machine.phase {
    case .aiming:
      let events = machine.aim(at: point)
      self.machine = machine
      // The crosshair is the last tier: it gives a point and nothing else.
      aim = TargetAim(point: point)
      apply(events)
    case .asking:
      cancel()
    default:
      break
    }
  }

  private func tick() {
    guard var machine else { return }
    let events = machine.tick()
    self.machine = machine
    apply(events)
  }

  private func apply(_ events: [ShowEvent]) {
    for event in events {
      let elapsed = startedAt.map { $0.duration(to: clock.now) } ?? .zero
      logger.info("\(String(describing: event), privacy: .public) at \(elapsed.formatted(), privacy: .public)")
      onEvent?(event, elapsed)
      switch event {
      case .entered(let phase): enter(phase)
      case .askBubbleDue: showBubble()
      }
    }
    scheduleTick()
  }

  private func scheduleTick() {
    tickTask?.cancel()
    tickTask = nil
    guard let deadline = machine?.nextDeadline else { return }
    tickTask = Task { [weak self, clock] in
      do {
        try await clock.sleep(until: deadline, tolerance: .milliseconds(2))
      } catch {
        return
      }
      self?.tick()
    }
  }

  private func enter(_ phase: ShowPhase) {
    guard let stage, let machine else { return }
    switch phase {
    case .aiming:
      stage.beginAiming()
      activate()
    case .entering:
      guard let target = machine.target else { return }
      stage.beginEntering(target: target)
    case .walking:
      guard let target = machine.target, let aim else { return }
      stage.prepare(target: target)
      stage.setInteractive(false)
      guard let layout = stage.layout(for: aim, targetCount: machine.targetCount) else { return }
      self.layout = layout
      stage.walk(layout)
      audio?.play(.bgm)
    case .asking:
      stage.setInteractive(true)
      activate()
      stage.point()
      audio?.play(.voice)
    case .kicking:
      stage.hideBubble()
      stage.setInteractive(false)
      stage.kick()
    case .exploding:
      if let layout {
        stage.explode(layout)
      }
      audio?.play(.explosion)
      let targetURLs = targetURLs
      trashTask = Task { [trash] in await trash(targetURLs) }
    case .rescuing:
      stage.rescue()
    case .flying:
      if let layout {
        stage.fly(layout)
      }
    case .done, .cancelled:
      finish(phase)
    }
  }

  private func showBubble() {
    guard let stage, let layout, let machine else { return }
    let swapIsPossible = onSwapRequested != nil && canSwap?() == true
    let onSwap: (() -> Void)? = swapIsPossible ? { [weak self] in self?.onSwapRequested?() } : nil
    stage.showBubble(
      layout,
      count: machine.targetCount,
      onConfirm: { [weak self] in self?.confirm() },
      onSwap: onSwap
    )
  }

  /// Takes keyboard focus so Esc reaches the panel even after another app took key during a
  /// click-through phase (spike section 5 and the Phase 1 default in section 10).
  private func activate() {
    if previousApp == nil, let front = NSWorkspace.shared.frontmostApplication,
      front.processIdentifier != ProcessInfo.processInfo.processIdentifier
    {
      previousApp = front
    }
    activation.activate()
  }

  /// Hands keyboard focus back to the app that had it before an interactive phase, but only if
  /// nothing else took it since and that app has a window on the current Space; activating an
  /// app whose windows live elsewhere would switch Spaces under the user.
  private func restoreActivation() {
    defer { previousApp = nil }
    guard NSApp.isActive, let previousApp, !previousApp.isTerminated else { return }
    guard hasWindowOnCurrentSpace(previousApp) else { return }
    NSApp.yieldActivation(to: previousApp)
    previousApp.activate()
  }

  private func hasWindowOnCurrentSpace(_ app: NSRunningApplication) -> Bool {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
    return windows.contains { window in
      window[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier
        && window[kCGWindowLayer as String] as? Int == 0
    }
  }

  private func finish(_ phase: ShowPhase) {
    let unaimedFan = UnaimedFan(targetCount: targetURLs.count, resolvedIcons: aim?.iconRects.count ?? 0)
    tickTask?.cancel()
    tickTask = nil
    audio?.stopAll()
    audio = nil
    stage?.tearDown()
    stage = nil
    restoreActivation()
    let trashTask = trashTask
    self.trashTask = nil
    Task { [weak self] in
      let outcome = await trashTask?.value
      self?.onFinished?(phase, outcome, unaimedFan)
    }
  }
}
