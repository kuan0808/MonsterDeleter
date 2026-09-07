/// What one show was aimed at, kept from its summon so the app can tell afterwards whether its
/// explosions landed in a ring around the click rather than on the files themselves.
///
/// The offer of icon aiming follows the experience, not the intent: a show cancelled with Esc, or
/// one that never ran, exploded nothing, so there is nothing to explain and nothing is recorded
/// (`Onboarding.recordUnaimedFan()`).
public struct UnaimedFan: Sendable, Hashable {
  /// How many items the show was summoned on.
  public let targetCount: Int
  /// How many of them the aiming tier found an icon rect for.
  public let resolvedIcons: Int

  public init(targetCount: Int, resolvedIcons: Int) {
    self.targetCount = targetCount
    self.resolvedIcons = resolvedIcons
  }

  /// Whether a show that ended in `phase` is the ring the app offers icon aiming after: it ran to
  /// the end, on two or more items, without one icon resolved.
  public func landedInARing(endingIn phase: ShowPhase) -> Bool {
    phase == .done && targetCount > 1 && resolvedIcons == 0
  }
}
