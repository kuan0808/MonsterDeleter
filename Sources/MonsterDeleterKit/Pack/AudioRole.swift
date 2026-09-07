/// The three sounds every character pack provides.
public enum AudioRole: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
  case bgm
  case voice
  case explosion
}
