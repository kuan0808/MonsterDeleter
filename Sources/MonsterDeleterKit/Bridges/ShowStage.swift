import AppKit
import SwiftUI

/// AppKit bridge. Everything visible during one show: an `OverlayPanel` per screen, the actor
/// layers, the aiming backdrop and the SwiftUI ask views hosted in the target screen's panel.
/// SwiftUI cannot host itself in a non-activating screen-saver-level panel nor drive Core
/// Animation layers, so the hosting and the layer work happen here. It only draws;
/// `ShowDirector` decides when.
@MainActor
public final class ShowStage {
  public var onClick: ((CGPoint) -> Void)?
  public var onCancel: (() -> Void)?

  private var pack: LoadedPack
  /// Fixed for the show: a swap changes the frames and texts, never the timing. Frame indices
  /// follow the pack on screen, durations follow the show.
  private let choreography: Choreography
  private var panels: [OverlayPanel] = []
  private var backdrops: [BackdropLayer] = []
  private var captions: [NSView] = []
  private var targetPanel: OverlayPanel?
  private var monster: ActorLayer?
  private var explosions: [ActorLayer] = []
  private var bubbleHost: NSView?
  private var buttonsHost: NSView?

  public init(pack: LoadedPack) {
    self.pack = pack
    choreography = pack.choreography
  }

  // MARK: Aiming

  /// Covers every screen with the dim, the caption and the crosshair.
  public func beginAiming() {
    for screen in NSScreen.screens {
      let panel = makePanel(for: screen)
      let backdrop = BackdropLayer(size: screen.frame.size)
      panel.overlayView.layer?.addSublayer(backdrop.layer)
      backdrop.fade(to: Float(choreography.backdropOpacity), over: choreography.backdropFadeIn)
      let caption = NSHostingView(rootView: AimingCaptionView())
      caption.sizingOptions = .intrinsicContentSize
      let size = caption.fittingSize
      caption.frame = CGRect(
        x: (screen.frame.width - size.width) / 2,
        y: screen.frame.height - size.height - 60,
        width: size.width,
        height: size.height
      )
      panel.overlayView.addSubview(caption)
      panel.overlayView.usesCrosshair = true
      panels.append(panel)
      backdrops.append(backdrop)
      captions.append(caption)
      panel.orderFrontRegardless()
    }
    let mouse = NSEvent.mouseLocation
    let underMouse = panels.first { $0.screenFrame.contains(mouse) } ?? panels.first
    for panel in panels {
      panel.ignoresMouseEvents = false
    }
    underMouse?.setInteractive(true)
  }

  /// Fades the dim out and keeps only the target screen's panel.
  public func beginEntering(target: CGPoint) {
    for backdrop in backdrops {
      backdrop.fade(to: 0, over: choreography.backdropFadeOut)
    }
    for caption in captions {
      caption.removeFromSuperview()
    }
    captions.removeAll()
    for panel in panels {
      panel.overlayView.usesCrosshair = false
      panel.ignoresMouseEvents = true
    }
    let panel = panelContaining(target)
    targetPanel = panel
    for other in panels where other !== panel {
      other.orderOut(nil)
    }
  }

  // MARK: Show

  /// Puts the target screen's panel up when the show skips aiming.
  public func prepare(target: CGPoint) {
    if targetPanel == nil {
      let screen = NSScreen.screens.first { $0.frame.contains(target) } ?? NSScreen.main ?? NSScreen.screens[0]
      let panel = makePanel(for: screen)
      panels.append(panel)
      targetPanel = panel
      panel.orderFrontRegardless()
    }
  }

  public var targetScreenFrame: CGRect? { targetPanel?.screenFrame }

  public func layout(for aim: TargetAim, targetCount: Int) -> ShowLayout? {
    guard let panel = targetPanel else { return nil }
    return choreography.layout(
      aim: aim,
      targetCount: targetCount,
      screen: panel.screenFrame,
      characterAspect: pack.aspect(of: .walk),
      explosionAspect: pack.aspect(of: .explosion)
    )
  }

  public func setInteractive(_ interactive: Bool) {
    targetPanel?.setInteractive(interactive)
  }

  public func walk(_ layout: ShowLayout) {
    guard let panel = targetPanel else { return }
    let actor = ActorLayer(contentsScale: panel.backingScaleFactor, frameDuration: choreography.frameDuration)
    actor.place(
      size: layout.characterSize,
      center: panel.localPoint(from: layout.start),
      mirrored: layout.entrySide.isMirrored
    )
    panel.overlayView.layer?.addSublayer(actor.layer)
    actor.play(pack.frames(for: .walk), repeats: true)
    actor.move(
      to: panel.localPoint(from: layout.stand),
      duration: choreography.walkDuration,
      easing: choreography.walkEasing
    )
    monster = actor
  }

  public func point() {
    let frames = pack.frames(for: .point)
    let range = choreography.pointFrames.clamped(to: 0...max(frames.count - 1, 0))
    monster?.play(Array(frames[range]), repeats: false)
  }

  /// The bubble names the whole selection, which can be larger than the drawn fan.
  public func showBubble(
    _ layout: ShowLayout,
    count: Int,
    onConfirm: @escaping () -> Void,
    onSwap: (() -> Void)?
  ) {
    guard let panel = targetPanel else { return }
    let texts = pack.descriptor.texts
    let tint = pack.descriptor.tint
    let bubble = NSHostingView(rootView: AskBubbleView(text: texts.bubble(count: count), tint: tint, onSwap: onSwap))
    bubble.sizingOptions = .intrinsicContentSize
    let bubbleFrame = layout.bubbleFrame(size: bubble.fittingSize)
    bubble.frame = CGRect(origin: panel.localPoint(from: bubbleFrame.origin), size: bubbleFrame.size)
    panel.overlayView.addSubview(bubble)
    bubbleHost = bubble

    let buttons = NSHostingView(rootView: AskButtonsView(texts: texts, tint: tint, onConfirm: onConfirm))
    buttons.sizingOptions = .intrinsicContentSize
    let buttonsFrame = layout.buttonsFrame(size: buttons.fittingSize)
    buttons.frame = CGRect(origin: panel.localPoint(from: buttonsFrame.origin), size: buttonsFrame.size)
    panel.overlayView.addSubview(buttons)
    buttonsHost = buttons
  }

  public func hideBubble() {
    bubbleHost?.removeFromSuperview()
    buttonsHost?.removeFromSuperview()
    bubbleHost = nil
    buttonsHost = nil
  }

  /// Dresses the standing monster in another pack during the ask: same spot, same phase, and the
  /// point frame the new pack's own range holds; the bubble comes down so the director can put
  /// the new one up. The show's timing stays on the choreography the stage was created with.
  public func swap(to newPack: LoadedPack, aim: TargetAim, targetCount: Int) -> ShowLayout? {
    pack = newPack
    hideBubble()
    guard let panel = targetPanel, let monster, let layout = layout(for: aim, targetCount: targetCount) else {
      return nil
    }
    monster.place(
      size: layout.characterSize,
      center: panel.localPoint(from: layout.stand),
      mirrored: layout.entrySide.isMirrored
    )
    let frames = pack.frames(for: .point)
    if let held = newPack.choreography.heldPointFrame(frameCount: frames.count) {
      monster.play([frames[held]], repeats: false)
    }
    return layout
  }

  public func kick() {
    monster?.play(pack.frames(for: .kick), repeats: false)
  }

  /// One explosion per item, all starting on the impact frame.
  public func explode(_ layout: ShowLayout) {
    guard let panel = targetPanel else { return }
    let frames = pack.frames(for: .explosion)
    for center in layout.explosionCenters {
      let actor = ActorLayer(contentsScale: panel.backingScaleFactor, frameDuration: choreography.frameDuration)
      actor.place(size: layout.explosionSize, center: panel.localPoint(from: center), mirrored: false)
      panel.overlayView.layer?.addSublayer(actor.layer)
      actor.play(frames, repeats: false)
      explosions.append(actor)
    }
  }

  /// The rescuer and the flight always face right, whichever side the monster came from.
  public func rescue() {
    monster?.setMirrored(false)
    monster?.play(pack.frames(for: .rescuer), repeats: false)
  }

  public func fly(_ layout: ShowLayout) {
    guard let panel = targetPanel else { return }
    removeExplosions()
    monster?.play(pack.frames(for: .fly), repeats: true)
    monster?.move(
      to: panel.localPoint(from: layout.exit),
      duration: choreography.flyDuration,
      easing: choreography.flyEasing
    )
  }

  /// Removes every panel and layer. Safe to call twice.
  public func tearDown() {
    hideBubble()
    monster?.remove()
    monster = nil
    removeExplosions()
    for caption in captions {
      caption.removeFromSuperview()
    }
    captions.removeAll()
    backdrops.removeAll()
    for panel in panels {
      panel.orderOut(nil)
      panel.close()
    }
    panels.removeAll()
    targetPanel = nil
  }

  // MARK: Checkpoints

  /// When the frames `phase` plays started, on Core Animation's clock: the explosion has actors
  /// of its own, every other phase dresses the monster. `nil` until those frames are up.
  public func animationStart(of phase: ShowPhase) -> CFTimeInterval? {
    phase == .exploding ? explosions.first?.animationStart : monster?.animationStart
  }

  /// What the target screen's panel shows at `showTime` on Core Animation's clock inside `rect`
  /// (AppKit global coordinates), one pixel per point whatever the screen's scale: the layer
  /// tree as the render server has it, drawn into a bitmap by this process, so no Screen
  /// Recording grant is needed. The tree is held at that moment for the drawing, so a capture a
  /// loaded machine reaches late still gets the frame and the position of the moment it asked
  /// for. `nil` before the panel is up or once it is down.
  public func snapshot(of rect: CGRect, at showTime: CFTimeInterval) -> CGImage? {
    guard let panel = targetPanel, let root = panel.overlayView.layer else { return nil }
    let width = Int(rect.width.rounded())
    let height = Int(rect.height.rounded())
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    let origin = panel.localPoint(from: rect.origin)
    context.translateBy(x: -origin.x, y: -origin.y)
    // Holding the tree at that moment (speed 0, local time = showTime) makes the render server
    // draw it there; the identity timing goes straight back, so the show catches up with its
    // own clock and later animations can keep beginning at `CACurrentMediaTime()`.
    root.speed = 0
    root.timeOffset = showTime
    CATransaction.flush()
    (root.presentation() ?? root).render(in: context)
    root.speed = 1
    root.timeOffset = 0
    CATransaction.flush()
    return context.makeImage()
  }

  // MARK: Helpers

  private func removeExplosions() {
    for explosion in explosions {
      explosion.remove()
    }
    explosions.removeAll()
  }

  private func makePanel(for screen: NSScreen) -> OverlayPanel {
    let panel = OverlayPanel(screen: screen)
    panel.overlayView.onClick = { [weak self] point in self?.onClick?(point) }
    panel.overlayView.onCancel = { [weak self] in self?.onCancel?() }
    return panel
  }

  private func panelContaining(_ point: CGPoint) -> OverlayPanel? {
    panels.first { $0.screenFrame.contains(point) } ?? panels.first
  }
}
