/// The six sprite sheets every character pack provides.
public enum SheetRole: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
  case walk
  case point
  case kick
  case explosion
  case rescuer
  case fly
}
