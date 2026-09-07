/// What an install ended in: the pack that was installed, and whether the app now wears it. A
/// choice made while the install was still loading outranks the install, and then the pack is on
/// disk without being current.
public struct PackInstallation: Sendable, Hashable {
  public let entry: PackEntry
  public let isCurrent: Bool

  public init(entry: PackEntry, isCurrent: Bool) {
    self.entry = entry
    self.isCurrent = isCurrent
  }
}
