import Foundation

/// When a checkpoint capture draws, and which moment of the show it draws.
///
/// The sprite frames run on Core Animation's clock from the moment the phase's frames began,
/// while the capture waits on a task a loaded machine can wake a whole frame slot late; drawing
/// whatever is on screen by then would catch the next frame and move a walking or flying
/// monster. So the capture always draws `showTime`, the checkpoint's own moment on that same
/// clock, and a task that arrives before it waits, so no capture is of a moment the screen has
/// not shown yet.
public struct CheckpointCapture: Sendable, Equatable {
  /// The moment of the show the capture draws, on Core Animation's clock.
  public let showTime: CFTimeInterval
  /// How long the capture waits before drawing: zero once the moment has passed.
  public let waits: Duration

  public init(
    _ checkpoint: ShowCheckpoint,
    animationStart: CFTimeInterval,
    now: CFTimeInterval,
    choreography: Choreography
  ) {
    let offset = checkpoint.offset(in: choreography)
    let parts = offset.components
    showTime = animationStart + Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    waits = showTime > now ? .seconds(showTime - now) : .zero
  }
}
