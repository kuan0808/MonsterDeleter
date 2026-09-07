import SwiftUI

/// One confirmation button: 16 pt, capsule, paper (or the pack's tint) at rest and the accent on
/// hover.
struct AskButton: View {
  let title: String
  let tint: PackTint?
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(isHovering ? Color.white : AskPalette.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(isHovering ? AskPalette.hover : AskPalette.paper(tint), in: Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}
