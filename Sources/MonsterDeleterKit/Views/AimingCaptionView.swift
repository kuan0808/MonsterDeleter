import SwiftUI

/// The hint shown at the top of every screen while the crosshair is up.
public struct AimingCaptionView: View {
  public init() {}

  public var body: some View {
    Text("Click the file to feed it to the monster. Press Esc to cancel.")
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(Color.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 9)
      .background(Color.black.opacity(0.7), in: Capsule())
      .fixedSize()
  }
}
