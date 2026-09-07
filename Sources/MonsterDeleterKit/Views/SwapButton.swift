import SwiftUI

/// The round button beside the bubble that dresses the show in the next pack.
struct SwapButton: View {
  static let size: CGFloat = 32

  let tint: PackTint?
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: "arrow.triangle.2.circlepath")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(isHovering ? Color.white : AskPalette.ink)
        .frame(width: Self.size, height: Self.size)
        .background(isHovering ? AskPalette.hover : AskPalette.paper(tint), in: Circle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("Swap character")
    .help("Swap to the next character pack")
  }
}
