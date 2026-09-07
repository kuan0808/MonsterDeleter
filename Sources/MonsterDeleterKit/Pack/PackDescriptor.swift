/// Everything a character pack declares: the decoded shape of `pack.json`.
///
/// Durations are plain seconds so the JSON stays readable. `Choreography` turns them into
/// `Duration` values and adds the geometry the packs do not control. Decoding goes through
/// `PackManifest`, which fills every absent or malformed field from `defaults`.
public struct PackDescriptor: Encodable, Sendable, Hashable {
  public var name: String
  public var description: String
  public var framesPerSecond: Int
  public var characterHeight: Double
  public var explosionHeight: Double
  /// Distance between the rings of a selection's explosion fan, in points.
  public var explosionFanRadius: Double
  public var sheets: [SheetRole: SheetDescriptor]
  public var pointFrames: ClosedRange<Int>
  public var kickImpactFrame: Int
  public var walkSeconds: Double
  public var flySeconds: Double
  public var audio: [AudioRole: AudioDescriptor]
  public var texts: PackTexts
  public var tint: PackTint?

  public init(
    name: String,
    description: String,
    framesPerSecond: Int = 8,
    characterHeight: Double = 250,
    explosionHeight: Double = 150,
    explosionFanRadius: Double = 75,
    sheets: [SheetRole: SheetDescriptor],
    pointFrames: ClosedRange<Int> = 11...14,
    kickImpactFrame: Int = 5,
    walkSeconds: Double = 4.5,
    flySeconds: Double = 2.0,
    audio: [AudioRole: AudioDescriptor],
    texts: PackTexts,
    tint: PackTint? = nil
  ) {
    self.name = name
    self.description = description
    self.framesPerSecond = framesPerSecond
    self.characterHeight = characterHeight
    self.explosionHeight = explosionHeight
    self.explosionFanRadius = explosionFanRadius
    self.sheets = sheets
    self.pointFrames = pointFrames
    self.kickImpactFrame = kickImpactFrame
    self.walkSeconds = walkSeconds
    self.flySeconds = flySeconds
    self.audio = audio
    self.texts = texts
    self.tint = tint
  }

  /// The built-in defaults every `pack.json` field falls back to: the original's numbers,
  /// `<role>.png` sheets in the standard grid, `<role>.wav` sounds at the original's volumes.
  public static let defaults = PackDescriptor(
    name: "",
    description: "",
    sheets: Dictionary(
      uniqueKeysWithValues: SheetRole.allCases.map { ($0, SheetDescriptor(file: "\($0.rawValue).png")) }
    ),
    audio: [
      .bgm: AudioDescriptor(file: "bgm.wav", volume: 0.5, loops: true),
      .voice: AudioDescriptor(file: "voice.wav", volume: 1.0),
      .explosion: AudioDescriptor(file: "explosion.wav", volume: 0.3),
    ],
    texts: PackTexts(
      bubble: "Hey, is it this one?",
      bubbleMany: "Hey, are these {count}?",
      confirm: "Yes",
      alternate: "Yes, eat it!"
    )
  )

  /// The built-in pack: generated silhouettes and tones, the original's numbers.
  public static let placeholder: PackDescriptor = {
    var pack = defaults
    pack.name = "Placeholder"
    pack.description = "Coloured silhouettes with frame numbers and generated tones. Stands in until real packs land."
    return pack
  }()

  /// The last four frames of the point sheet: 11...14 of the standard 15.
  public static func defaultPointFrames(frameCount: Int) -> ClosedRange<Int> {
    max(frameCount - 4, 0)...max(frameCount - 1, 0)
  }

  /// Frame 5 of the kick sheet, or its last frame on a shorter sheet.
  public static func defaultKickImpactFrame(frameCount: Int) -> Int {
    min(5, max(frameCount - 1, 0))
  }
}
