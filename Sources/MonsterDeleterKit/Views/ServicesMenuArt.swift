import SwiftUI

/// The Finder right-click menu with **Services > Feed to Monster** picked out, drawn rather than
/// screenshotted: the hardest step in the product is finding that item, and a paragraph is the
/// weakest way to teach it. Drawing it in system materials keeps it right in both appearances and
/// through a macOS restyle, which a screenshot would not survive.
public struct ServicesMenuArt: View {
  /// The whole menu, or just the trail of three steps for the app window's reminder strip.
  public enum Detail: Sendable { case full, trail }

  private let detail: Detail

  public init(_ detail: Detail = .full) {
    self.detail = detail
  }

  public var body: some View {
    Group {
      switch detail {
      case .full: fullMenu
      case .trail: trail
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "In Finder, right-click a file, a folder, or a selection, then choose Services > Feed to Monster."
    )
  }

  private var fullMenu: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(spacing: 4) {
        Image(systemName: "doc.fill")
          .font(.system(size: 26))
          .foregroundStyle(.tertiary)
        Text("Report.pdf")
          .font(.system(size: 9))
          .foregroundStyle(.tertiary)
      }
      .padding(.top, 10)

      VStack(alignment: .leading, spacing: 1) {
        ForEach(["Open", "Move to Trash", "Get Info", "Rename…", "Tags…"], id: \.self) { item in
          row(item, isHighlighted: false)
        }
        Divider().padding(.vertical, 2)
        row("Services", isHighlighted: true, chevron: true)
      }
      .padding(4)
      .frame(width: 132)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
      .shadow(color: .black.opacity(0.18), radius: 7, y: 3)

      VStack(alignment: .leading, spacing: 1) {
        row("Feed to Monster", isHighlighted: true)
        row("Services Settings…", isHighlighted: false)
      }
      .padding(4)
      .frame(width: 132)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
      .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
      .padding(.top, 92)
    }
  }

  private func row(_ title: String, isHighlighted: Bool, chevron: Bool = false) -> some View {
    HStack(spacing: 4) {
      Text(title)
        .lineLimit(1)
      Spacer(minLength: 2)
      if chevron {
        Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold))
      }
    }
    .font(.system(size: 10))
    .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      if isHighlighted {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor)
      }
    }
  }

  private var trail: some View {
    HStack(spacing: 8) {
      step("Right-click", detail: "a file or folder", isLast: false)
      step("Services", detail: "last item", isLast: false)
      step("Feed to Monster", detail: nil, isLast: true)
    }
  }

  @ViewBuilder
  private func step(_ title: String, detail: String?, isLast: Bool) -> some View {
    VStack(spacing: 1) {
      Text(title)
        .font(.system(size: 11, weight: isLast ? .semibold : .regular))
        .foregroundStyle(isLast ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
      if let detail {
        Text(detail).font(.system(size: 9)).foregroundStyle(.tertiary)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(isLast ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
    )
    if !isLast {
      Image(systemName: "chevron.right")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.tertiary)
    }
  }
}
