import Foundation

/// `pack.json` as read from a pack folder: every field optional, unknown fields ignored, and a
/// malformed value replaced by the built-in default with a warning naming the field. Decoding
/// throws only when the data is not a JSON object at all; a value never crashes the app.
public struct PackManifest: Sendable, Hashable {
  public private(set) var descriptor: PackDescriptor
  /// Roles the manifest names a sheet file for. The others fall back to the built-in sheet.
  public private(set) var declaredSheets: Set<SheetRole>
  /// Roles the manifest names a sound file for. The others fall back to the built-in sound.
  public private(set) var declaredAudio: Set<AudioRole>
  /// Whether the JSON gave a `pointFrames` the decoder accepted, so a pack source that swaps a
  /// sheet knows whether the range is the author's or a default computed from the dropped grid.
  public private(set) var explicitPointFrames: Bool
  /// Whether the JSON gave a `kickImpactFrame` the decoder accepted.
  public private(set) var explicitKickImpactFrame: Bool
  /// One line per malformed value, `field: reason`, for the log.
  public private(set) var warnings: [String]

  public init(json: Data) throws {
    self = try JSONDecoder().decode(PackManifest.self, from: json)
  }
}

extension PackManifest: Decodable {
  public init(from decoder: any Decoder) throws {
    let root = try decoder.container(keyedBy: AnyKey.self)
    var reader = LenientReader()
    var pack = PackDescriptor.defaults

    pack.name = reader.value("name", in: root, fallback: pack.name)
    pack.description = reader.value("description", in: root, fallback: pack.description)
    pack.framesPerSecond = reader.value("framesPerSecond", in: root, fallback: pack.framesPerSecond) {
      (1...120).contains($0)
    }
    pack.characterHeight = reader.value("characterHeight", in: root, fallback: pack.characterHeight, Self.isHeight)
    pack.explosionHeight = reader.value("explosionHeight", in: root, fallback: pack.explosionHeight, Self.isHeight)
    pack.explosionFanRadius = reader.value(
      "explosionFanRadius",
      in: root,
      fallback: pack.explosionFanRadius,
      Self.isFanRadius
    )
    pack.walkSeconds = reader.value("walkSeconds", in: root, fallback: pack.walkSeconds, Self.isSeconds)
    pack.flySeconds = reader.value("flySeconds", in: root, fallback: pack.flySeconds, Self.isSeconds)
    pack.tint = reader.value("tint", in: root, fallback: nil as PackTint?)

    var declaredSheets: Set<SheetRole> = []
    if let sheets = reader.object("sheets", in: root) {
      for key in sheets.allKeys {
        guard let role = SheetRole(rawValue: key.stringValue) else {
          reader.warn("sheets.\(key.stringValue)", "is not one of \(SheetRole.allCases.map(\.rawValue))")
          continue
        }
        guard let sheet = reader.object(key.stringValue, in: sheets, path: "sheets.") else { continue }
        let path = "sheets.\(role.rawValue)."
        let fallback = pack.sheets[role] ?? SheetDescriptor(file: "\(role.rawValue).png")
        let file = reader.file("file", in: sheet, path: path)
        pack.sheets[role] = SheetDescriptor(
          file: file ?? fallback.file,
          columns: reader.value("columns", in: sheet, path: path, fallback: fallback.columns, Self.isGridSide),
          rows: reader.value("rows", in: sheet, path: path, fallback: fallback.rows, Self.isGridSide)
        )
        if file != nil {
          declaredSheets.insert(role)
        }
      }
    }

    var declaredAudio: Set<AudioRole> = []
    if let audio = reader.object("audio", in: root) {
      for key in audio.allKeys {
        guard let role = AudioRole(rawValue: key.stringValue) else {
          reader.warn("audio.\(key.stringValue)", "is not one of \(AudioRole.allCases.map(\.rawValue))")
          continue
        }
        guard let sound = reader.object(key.stringValue, in: audio, path: "audio.") else { continue }
        let path = "audio.\(role.rawValue)."
        let fallback = pack.audio[role] ?? AudioDescriptor(file: "\(role.rawValue).wav", volume: 1)
        let file = reader.file("file", in: sound, path: path)
        pack.audio[role] = AudioDescriptor(
          file: file ?? fallback.file,
          volume: reader.value("volume", in: sound, path: path, fallback: fallback.volume) { (0...1).contains($0) },
          loops: reader.value("loops", in: sound, path: path, fallback: fallback.loops)
        )
        if file != nil {
          declaredAudio.insert(role)
        }
      }
    }

    if let texts = reader.object("texts", in: root) {
      pack.texts.bubble = reader.value("bubble", in: texts, path: "texts.", fallback: pack.texts.bubble)
      pack.texts.bubbleMany = reader.value("bubbleMany", in: texts, path: "texts.", fallback: pack.texts.bubbleMany)
      pack.texts.confirm = reader.value("confirm", in: texts, path: "texts.", fallback: pack.texts.confirm)
      pack.texts.alternate = reader.value("alternate", in: texts, path: "texts.", fallback: pack.texts.alternate)
    }

    // Frame indices are checked against the grids decoded above, so the defaults fit the sheet.
    let pointCount = pack.sheets[.point]?.frameCount ?? SheetDescriptor.standardFrameCount
    let kickCount = pack.sheets[.kick]?.frameCount ?? SheetDescriptor.standardFrameCount
    pack.pointFrames = reader.value(
      "pointFrames",
      in: root,
      fallback: PackDescriptor.defaultPointFrames(frameCount: pointCount)
    ) { $0.lowerBound >= 0 && $0.upperBound < pointCount }
    pack.kickImpactFrame = reader.value(
      "kickImpactFrame",
      in: root,
      fallback: PackDescriptor.defaultKickImpactFrame(frameCount: kickCount)
    ) { (0..<kickCount).contains($0) }

    descriptor = pack
    self.declaredSheets = declaredSheets
    self.declaredAudio = declaredAudio
    explicitPointFrames = reader.accepted.contains("pointFrames")
    explicitKickImpactFrame = reader.accepted.contains("kickImpactFrame")
    warnings = reader.warnings
  }

  private static func isHeight(_ value: Double) -> Bool { value.isFinite && (1...4000).contains(value) }
  private static func isFanRadius(_ value: Double) -> Bool { value.isFinite && (0...4000).contains(value) }
  private static func isSeconds(_ value: Double) -> Bool { value.isFinite && value > 0 && value <= 60 }
  /// Bounded so `columns * rows` stays a sane frame count and can never overflow.
  private static func isGridSide(_ value: Int) -> Bool { (1...4096).contains(value) }
}

/// A string key for reading JSON objects whose keys are only known at run time.
private struct AnyKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }

  init(_ name: String) { stringValue = name }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}

/// Reads one field at a time and collects a warning instead of throwing.
private struct LenientReader {
  private(set) var warnings: [String] = []
  /// Fields the JSON gave a value the reader took, by full path.
  private(set) var accepted: Set<String> = []

  mutating func warn(_ field: String, _ reason: String) {
    warnings.append("\(field): \(reason); using the default")
  }

  /// The value at `key` when present, well-formed and accepted by `isValid`; `fallback` otherwise.
  mutating func value<Value: Decodable>(
    _ key: String,
    in container: KeyedDecodingContainer<AnyKey>,
    path: String = "",
    fallback: Value,
    _ isValid: (Value) -> Bool = { _ in true }
  ) -> Value {
    guard container.contains(AnyKey(key)) else { return fallback }
    let decoded: Value
    do {
      decoded = try container.decode(Value.self, forKey: AnyKey(key))
    } catch {
      warn(path + key, Self.reason(for: error))
      return fallback
    }
    guard isValid(decoded) else {
      warn(path + key, "\(decoded) is out of range")
      return fallback
    }
    accepted.insert(path + key)
    return decoded
  }

  /// A nested object, or `nil` when absent or not an object.
  mutating func object(
    _ key: String,
    in container: KeyedDecodingContainer<AnyKey>,
    path: String = ""
  ) -> KeyedDecodingContainer<AnyKey>? {
    guard container.contains(AnyKey(key)) else { return nil }
    do {
      return try container.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(key))
    } catch {
      warn(path + key, Self.reason(for: error))
      return nil
    }
  }

  /// A non-empty file name; `nil` when the key is absent, and `nil` with a warning when its
  /// value is not a non-empty string. An absent name means the role's default-named file.
  mutating func file(_ key: String, in container: KeyedDecodingContainer<AnyKey>, path: String) -> String? {
    guard container.contains(AnyKey(key)) else { return nil }
    let name = value(key, in: container, path: path, fallback: "") { !$0.isEmpty }
    return name.isEmpty ? nil : name
  }

  private static func reason(for error: any Error) -> String {
    switch error {
    case DecodingError.typeMismatch(let type, _): return "is not \(Self.describe(type))"
    case DecodingError.valueNotFound: return "is null"
    case DecodingError.dataCorrupted(let context): return context.debugDescription
    default: return String(describing: error)
    }
  }

  private static func describe(_ type: Any.Type) -> String {
    switch type {
    case is String.Type: return "a string"
    case is Bool.Type: return "true or false"
    case is Int.Type, is Int64.Type: return "a whole number"
    case is Double.Type: return "a number"
    case is ClosedRange<Int>.Type, is [Any].Type: return "a pair of frame indices"
    default: return "an object"
    }
  }
}
