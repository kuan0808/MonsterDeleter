/// An optional pack colour, written in `pack.json` as `#RRGGBB`. It paints the ask bubble and the
/// buttons so a re-skin with no artwork of its own still looks different.
public struct PackTint: Codable, Sendable, Hashable {
  public var red: UInt8
  public var green: UInt8
  public var blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// Parses `#RRGGBB` or `RRGGBB`, case-insensitive.
  public init?(hex: String) {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
      return nil
    }
    self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
  }

  public var hex: String {
    let value = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    let digits = String(value, radix: 16, uppercase: true)
    return "#" + String(repeating: "0", count: 6 - digits.count) + digits
  }

  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    guard let tint = PackTint(hex: text) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "expected #RRGGBB, got \"\(text)\"")
      )
    }
    self = tint
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(hex)
  }
}
