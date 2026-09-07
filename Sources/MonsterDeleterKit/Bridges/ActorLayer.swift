import QuartzCore

/// Core Animation bridge. One actor (the monster or the explosion) as a `CALayer` whose frames
/// step in the render server at exactly the pack's frame rate, independent of main-thread load.
/// SwiftUI's animation runs on the main thread and cannot promise 125 ms frame steps.
@MainActor
public final class ActorLayer {
  public let layer = CALayer()
  /// When the frames of the sheet playing now started, on the media clock.
  public private(set) var animationStart: CFTimeInterval = 0
  private let frameDuration: Duration

  public init(contentsScale: CGFloat, frameDuration: Duration) {
    self.frameDuration = frameDuration
    layer.contentsGravity = .resizeAspect
    layer.contentsScale = contentsScale
    layer.minificationFilter = .linear
    layer.magnificationFilter = .linear
    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    // A standalone layer animates every property change implicitly; the show sets them exactly.
    layer.actions = [
      "contents": NSNull(), "position": NSNull(), "bounds": NSNull(),
      "transform": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
    ]
  }

  public func place(size: CGSize, center: CGPoint, mirrored: Bool) {
    layer.bounds = CGRect(origin: .zero, size: size)
    layer.position = center
    setMirrored(mirrored)
  }

  public func setMirrored(_ mirrored: Bool) {
    layer.transform = mirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
  }

  /// Plays `frames` in order, each for one frame duration; loops when `repeats` is set,
  /// otherwise holds the last frame.
  public func play(_ frames: [CGImage], repeats: Bool) {
    guard !frames.isEmpty else { return }
    let animation = CAKeyframeAnimation(keyPath: "contents")
    animation.values = frames
    // Discrete mode wants one more key time than values: frame i shows from time i/n to (i+1)/n.
    animation.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
    animation.calculationMode = .discrete
    animation.duration = seconds(frameDuration * frames.count)
    animation.repeatCount = repeats ? .infinity : 1
    animation.isRemovedOnCompletion = false
    // Both ends: the sheet's last frame holds after the animation, and its first frame is what
    // the phase's very first moment draws, rather than the layer's model contents.
    animation.fillMode = .both
    // The frames follow the show's clock, not the moment the transaction commits: the first
    // commit of a fresh panel can come tens of milliseconds late, enough to shift a frame.
    let start = CACurrentMediaTime()
    animation.beginTime = start
    animationStart = start
    layer.contents = frames[frames.count - 1]
    layer.add(animation, forKey: "frames")
  }

  /// Slides the layer's centre to `destination`.
  public func move(to destination: CGPoint, duration: Duration, easing: Easing) {
    let animation = CABasicAnimation(keyPath: "position")
    animation.fromValue = NSValue(point: layer.presentation()?.position ?? layer.position)
    animation.toValue = NSValue(point: destination)
    animation.duration = seconds(duration)
    let points = easing.controlPoints
    animation.timingFunction = CAMediaTimingFunction(controlPoints: points.x1, points.y1, points.x2, points.y2)
    animation.beginTime = CACurrentMediaTime()
    // The move begins a hair after the frames of the same phase; filling backwards keeps the
    // layer on its starting point until then instead of jumping to the model destination.
    animation.fillMode = .backwards
    layer.position = destination
    layer.add(animation, forKey: "move")
  }

  public func remove() {
    layer.removeAllAnimations()
    layer.removeFromSuperlayer()
  }

  private func seconds(_ duration: Duration) -> CFTimeInterval {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }
}
