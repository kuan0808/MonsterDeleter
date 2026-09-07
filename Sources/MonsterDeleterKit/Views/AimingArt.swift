import SwiftUI

/// What the Accessibility permission actually buys, drawn side by side: with it off every
/// explosion of a selection falls into the ring around the point you clicked, with it on each one
/// lands on the file it is deleting. It is the whole explanation, and shorter than the paragraph it
/// replaces.
public struct AimingArt: View {
  public init() {}

  public var body: some View {
    HStack(alignment: .top, spacing: 12) {
      panel(isAimed: false)
      panel(isAimed: true)
    }
    .accessibilityHidden(true)
  }

  private let iconWidth: CGFloat = 15
  private let iconHeight: CGFloat = 18
  private let rowSpacing: CGFloat = 9
  private let burstSize: CGFloat = 21

  private func panel(isAimed: Bool) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(isAimed ? "On" : "Off")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isAimed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
      HStack(alignment: .center, spacing: 10) {
        files(hit: isAimed)
        if !isAimed {
          ring
        }
      }
      .frame(height: 3 * iconHeight + 2 * rowSpacing)
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(isAimed ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.05))
    )
  }

  /// Three files in a Finder list; with the permission, each one wears its own explosion.
  private func files(hit: Bool) -> some View {
    VStack(alignment: .leading, spacing: rowSpacing) {
      ForEach(0..<3, id: \.self) { row in
        HStack(spacing: 6) {
          ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
              .strokeBorder(.tertiary, lineWidth: 1)
              .frame(width: iconWidth, height: iconHeight)
            if hit {
              Burst()
                .fill(Color.accentColor)
                .frame(width: burstSize, height: burstSize)
            }
          }
          RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(.quaternary)
            .frame(width: 46 - CGFloat(row) * 9, height: 5)
        }
      }
    }
  }

  /// The fallback: the same three explosions evenly spaced on a ring around the pointer, which is
  /// exactly what `ExplosionFan` draws when no icon could be read.
  private var ring: some View {
    ZStack {
      ForEach(0..<3, id: \.self) { hit in
        Burst()
          .fill(.secondary)
          .frame(width: burstSize, height: burstSize)
          .offset(x: 17)
          .rotationEffect(.degrees(Double(hit) * 120 - 90))
      }
      Image(systemName: "cursorarrow")
        .font(.system(size: 12))
        .foregroundStyle(.primary)
    }
    .frame(width: 56, height: 56)
  }
}

/// A twelve-point starburst: SF Symbols has no explosion, and the show's own frames are a pack's
/// art rather than a shape the settings row can borrow.
private struct Burst: Shape {
  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outer = min(rect.width, rect.height) / 2
    let inner = outer * 0.46
    var path = Path()
    for point in 0..<24 {
      let angle = Double(point) / 24 * 2 * .pi - .pi / 2
      let radius = point.isMultiple(of: 2) ? outer : inner
      let next = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
      if point == 0 { path.move(to: next) } else { path.addLine(to: next) }
    }
    path.closeSubpath()
    return path
  }
}
