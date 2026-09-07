import SwiftUI

/// The original's ask colours: paper at 240/255, ink #1c1c1e, hover #007aff.
/// A pack's tint replaces the paper.
enum AskPalette {
  static let paper = Color(white: 240.0 / 255.0)
  static let ink = Color(red: 0x1c / 255.0, green: 0x1c / 255.0, blue: 0x1e / 255.0)
  static let hover = Color(red: 0, green: 0x7a / 255.0, blue: 1)

  static func paper(_ tint: PackTint?) -> Color {
    guard let tint else { return paper }
    return Color(red: Double(tint.red) / 255, green: Double(tint.green) / 255, blue: Double(tint.blue) / 255)
  }
}
