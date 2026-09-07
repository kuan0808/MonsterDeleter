import QuartzCore

/// Core Animation bridge. The dim that covers a screen while aiming: fades in over the
/// choreography's fade-in time and out over the `entering` phase. SwiftUI's opacity animation is
/// driven on the main thread, so it stalls with it; this fade is timed by the render server and
/// keeps stepping while the main thread is busy trashing a file.
@MainActor
public final class BackdropLayer {
  public let layer = CALayer()

  public init(size: CGSize) {
    layer.frame = CGRect(origin: .zero, size: size)
    layer.backgroundColor = CGColor(gray: 0, alpha: 1)
    layer.opacity = 0
    layer.actions = ["opacity": NSNull()]
  }

  public func fade(to opacity: Float, over duration: Duration) {
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
    animation.toValue = opacity
    let parts = duration.components
    animation.duration = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    layer.opacity = opacity
    layer.add(animation, forKey: "fade")
  }
}
