import SwiftUI

/// Both buttons confirm, as in the original; cancelling is Esc or a click outside.
///
/// Under them, in the app's own words rather than the pack's, the two things a first-timer needs at
/// the moment they decide: the file is going to the Trash and not anywhere worse, and Esc gets them
/// out. This is the only place both are certain to be read, and a pack cannot overwrite it.
public struct AskButtonsView: View {
  public let texts: PackTexts
  public let tint: PackTint?
  public let onConfirm: () -> Void

  public init(texts: PackTexts, tint: PackTint? = nil, onConfirm: @escaping () -> Void) {
    self.texts = texts
    self.tint = tint
    self.onConfirm = onConfirm
  }

  public var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 12) {
        AskButton(title: texts.confirm, tint: tint, action: onConfirm)
        AskButton(title: texts.alternate, tint: tint, action: onConfirm)
      }
      hint
    }
    .padding(6)
    .fixedSize()
  }

  private var hint: some View {
    HStack(spacing: 6) {
      Image(systemName: "arrow.up.bin")
        .imageScale(.small)
      Text("Goes to the Trash")
      Text("·")
        .foregroundStyle(Color.white.opacity(0.5))
      Text("Esc cancels")
    }
    .font(.system(size: 12, weight: .medium))
    .foregroundStyle(Color.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    .background(Color.black.opacity(0.65), in: Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Everything goes to the Trash. Press Escape to cancel.")
  }
}
