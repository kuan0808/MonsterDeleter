/// The phases of one show, in order. `aiming` and `entering` only occur when the target point is
/// unknown and the user aims with the crosshair.
public enum ShowPhase: String, Sendable, Hashable, CaseIterable {
  /// Crosshair over every screen; the user clicks the file. Interactive.
  case aiming
  /// The aiming backdrop fades out.
  case entering
  /// The monster walks in from the chosen side.
  case walking
  /// The monster points and asks; the bubble appears once the point frames are done. Interactive.
  case asking
  /// Kick frames up to the impact frame.
  case kicking
  /// From the impact frame: explosion, sound and trash; the kick sheet finishes.
  case exploding
  /// The rescuer enters while the explosion fades.
  case rescuing
  /// The flight out past the right edge.
  case flying
  case done
  case cancelled

  /// Plan decision 7: interactive only while aiming and asking; click-through otherwise.
  public var isInteractive: Bool { self == .aiming || self == .asking }

  public var isTerminal: Bool { self == .done || self == .cancelled }

  /// The phase that follows once this timed phase's duration has elapsed.
  public var successor: ShowPhase? {
    switch self {
    case .entering: return .walking
    case .walking: return .asking
    case .kicking: return .exploding
    case .exploding: return .rescuing
    case .rescuing: return .flying
    case .flying: return .done
    case .aiming, .asking, .done, .cancelled: return nil
    }
  }
}
