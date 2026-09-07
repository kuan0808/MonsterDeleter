/// What the machine reports back to whoever drives it. Every effect (animation, sound, trash,
/// panel interactivity) hangs off one of these.
public enum ShowEvent: Sendable, Hashable {
  case entered(ShowPhase)
  /// The point frames are done; show the bubble and the buttons.
  case askBubbleDue
}
