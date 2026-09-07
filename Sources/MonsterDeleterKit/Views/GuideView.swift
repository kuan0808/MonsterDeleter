import SwiftUI

/// The guide as a sheet over the app window: one row per answer, scrollable, Esc or Done to leave.
public struct GuideView: View {
  private let dismiss: () -> Void

  public init(dismiss: @escaping () -> Void) {
    self.dismiss = dismiss
  }

  public var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Guide")
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Button("Done", action: dismiss)
          .keyboardShortcut(.defaultAction)
      }
      .padding(16)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          ForEach(Guide.entries) { entry in
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: entry.symbol)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 3) {
                Text(entry.question)
                  .font(.system(size: 13, weight: .semibold))
                Text(entry.answer)
                  .font(.callout)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(width: 460, height: 520)
    .onExitCommand(perform: dismiss)
  }
}
