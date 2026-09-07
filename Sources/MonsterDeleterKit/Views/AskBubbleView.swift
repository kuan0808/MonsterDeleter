import SwiftUI

/// The monster's question, in the original's 20 pt semibold on a rounded paper bubble, with the
/// swap button beside it when there is another pack to swap to. A blank of the button's width
/// on the other side keeps the bubble, and its tail, centred over the head.
public struct AskBubbleView: View {
  public let text: String
  public let tint: PackTint?
  public let onSwap: (() -> Void)?

  public init(text: String, tint: PackTint? = nil, onSwap: (() -> Void)? = nil) {
    self.text = text
    self.tint = tint
    self.onSwap = onSwap
  }

  public var body: some View {
    HStack(spacing: 8) {
      if onSwap != nil {
        Color.clear
          .frame(width: SwapButton.size, height: SwapButton.size)
          .allowsHitTesting(false)
      }
      bubble
      if let onSwap {
        SwapButton(tint: tint, action: onSwap)
      }
    }
    .padding(.bottom, 10)
    .fixedSize()
  }

  private var bubble: some View {
    Text(text)
      .font(.system(size: 20, weight: .semibold))
      .foregroundStyle(AskPalette.ink)
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .background(AskPalette.paper(tint), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(alignment: .bottom) {
        BubbleTail()
          .fill(AskPalette.paper(tint))
          .frame(width: 20, height: 10)
          .offset(y: 9)
      }
  }
}
