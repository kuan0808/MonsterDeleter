import CoreGraphics
import CoreText
import Foundation

/// Paints the placeholder sheets: a coloured silhouette per frame with the frame number, so every
/// sheet, grid, frame index and mirroring decision can be checked by eye before real art exists.
///
/// Characters face right. Frames are laid out row-major from the top-left, like the upstream sheets.
public enum PlaceholderSheetRenderer {
  /// Character frames are 2x of the displayed 144 x 256 pt (aspect 0.5625, like upstream's 225 x 400).
  public static let characterFrameSize = CGSize(width: 288, height: 512)
  /// Explosion frames are 2x of the displayed 120 x 160 pt (aspect 0.75, like upstream's 1440 x 1920).
  public static let explosionFrameSize = CGSize(width: 240, height: 320)

  public static func render(role: SheetRole, columns: Int, rows: Int) -> CGImage? {
    let frameSize = role == .explosion ? explosionFrameSize : characterFrameSize
    let width = Int(frameSize.width) * columns
    let height = Int(frameSize.height) * rows
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    let frameCount = columns * rows
    for index in 0..<frameCount {
      let column = index % columns
      let row = index / columns
      // Core Graphics is bottom-up; row 0 is the top strip of the sheet.
      let origin = CGPoint(
        x: CGFloat(column) * frameSize.width,
        y: CGFloat(rows - 1 - row) * frameSize.height
      )
      context.saveGState()
      context.translateBy(x: origin.x, y: origin.y)
      context.clip(to: CGRect(origin: .zero, size: frameSize))
      if role == .explosion {
        paintExplosion(in: context, size: frameSize, frame: index, count: frameCount)
      } else {
        paintCharacter(in: context, size: frameSize, role: role, frame: index, count: frameCount)
      }
      paintLabel("\(index)", in: context, size: frameSize)
      context.restoreGState()
    }
    return context.makeImage()
  }

  // MARK: Character

  private static func paintCharacter(in context: CGContext, size: CGSize, role: SheetRole, frame: Int, count: Int) {
    let w = size.width
    let h = size.height
    let cx = w / 2
    let phase = Double(frame) / Double(count)
    let bodyColor = bodyColor(for: role)
    let legLength = 0.34 * h
    let hipY = 0.36 * h
    context.setLineCap(.round)

    // Legs.
    context.setStrokeColor(bodyColor)
    context.setLineWidth(0.09 * w)
    let swing: CGFloat = role == .walk || role == .fly ? CGFloat(sin(phase * 2 * .pi)) * 0.16 * w : 0
    let kickLift: CGFloat = role == .kick ? kickAmount(frame: frame, count: count) : 0
    let leftFoot = CGPoint(x: cx - 0.12 * w - swing, y: hipY - legLength)
    let rightFoot =
      role == .kick
      ? CGPoint(x: cx + 0.12 * w + kickLift * 0.38 * w, y: hipY - legLength + kickLift * 0.42 * h)
      : CGPoint(x: cx + 0.12 * w + swing, y: hipY - legLength)
    stroke(from: CGPoint(x: cx - 0.1 * w, y: hipY), to: leftFoot, in: context)
    stroke(from: CGPoint(x: cx + 0.1 * w, y: hipY), to: rightFoot, in: context)

    // Body.
    context.setFillColor(bodyColor)
    let body = CGRect(x: cx - 0.21 * w, y: 0.34 * h, width: 0.42 * w, height: 0.38 * h)
    context.addPath(CGPath(roundedRect: body, cornerWidth: 0.12 * w, cornerHeight: 0.12 * w, transform: nil))
    context.fillPath()

    // Cape for the flight so the fly sheet reads differently from the walk.
    if role == .fly || role == .rescuer {
      context.setFillColor(accentColor(for: role))
      context.move(to: CGPoint(x: cx - 0.2 * w, y: 0.68 * h))
      context.addLine(to: CGPoint(x: cx - 0.46 * w, y: 0.42 * h + swing))
      context.addLine(to: CGPoint(x: cx - 0.16 * w, y: 0.38 * h))
      context.closePath()
      context.fillPath()
    }

    // Arms.
    context.setStrokeColor(bodyColor)
    context.setLineWidth(0.07 * w)
    let shoulderY = 0.64 * h
    let pointing = role == .point && PackDescriptor.placeholder.pointFrames.contains(frame)
    let rightHand =
      pointing
      ? CGPoint(x: cx + 0.48 * w, y: 0.66 * h)
      : CGPoint(x: cx + 0.26 * w, y: 0.44 * h + swing * 0.5)
    stroke(
      from: CGPoint(x: cx - 0.18 * w, y: shoulderY),
      to: CGPoint(x: cx - 0.26 * w, y: 0.44 * h - swing * 0.5),
      in: context
    )
    stroke(from: CGPoint(x: cx + 0.18 * w, y: shoulderY), to: rightHand, in: context)

    // Head, eye and pupil; the pupil sits to the right so the facing direction is visible.
    context.setFillColor(bodyColor)
    context.fillEllipse(in: CGRect(x: cx - 0.17 * w, y: 0.7 * h, width: 0.34 * w, height: 0.34 * w))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: cx + 0.03 * w, y: 0.8 * h, width: 0.1 * w, height: 0.1 * w))
    context.setFillColor(CGColor(gray: 0.1, alpha: 1))
    context.fillEllipse(in: CGRect(x: cx + 0.07 * w, y: 0.82 * h, width: 0.05 * w, height: 0.05 * w))
  }

  /// How far the kicking leg is raised: builds up to the impact frame, then drops back.
  private static func kickAmount(frame: Int, count: Int) -> CGFloat {
    let impact = PackDescriptor.placeholder.kickImpactFrame
    if frame <= impact {
      return CGFloat(frame) / CGFloat(max(impact, 1))
    }
    let remaining = CGFloat(count - 1 - frame) / CGFloat(max(count - 1 - impact, 1))
    return max(remaining, 0)
  }

  // MARK: Explosion

  private static func paintExplosion(in context: CGContext, size: CGSize, frame: Int, count: Int) {
    let progress = Double(frame) / Double(max(count - 1, 1))
    let growth = Easing.outQuad.value(at: min(progress * 2, 1))
    let alpha = progress < 0.6 ? 1.0 : max(0, 1 - (progress - 0.6) / 0.4)
    let center = CGPoint(x: size.width / 2, y: size.height * 0.55)
    let maxRadius = size.width * 0.46
    let radius = maxRadius * CGFloat(0.25 + 0.75 * growth)
    let rings: [(CGFloat, CGColor)] = [
      (1.0, CGColor(red: 0.95, green: 0.35, blue: 0.1, alpha: alpha)),
      (0.7, CGColor(red: 1.0, green: 0.7, blue: 0.15, alpha: alpha)),
      (0.4, CGColor(red: 1.0, green: 0.95, blue: 0.6, alpha: alpha)),
    ]
    for (scale, color) in rings {
      context.setFillColor(color)
      let r = radius * scale
      context.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }
    // Spikes rotate with the frame so consecutive frames are distinguishable.
    context.setStrokeColor(CGColor(red: 1.0, green: 0.55, blue: 0.1, alpha: alpha))
    context.setLineWidth(size.width * 0.03)
    context.setLineCap(.round)
    for spike in 0..<8 {
      let angle = Double(spike) / 8 * 2 * .pi + Double(frame) * 0.3
      let inner = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
      let outer = CGPoint(x: center.x + cos(angle) * radius * 1.35, y: center.y + sin(angle) * radius * 1.35)
      stroke(from: inner, to: outer, in: context)
    }
  }

  // MARK: Label

  private static func paintLabel(_ text: String, in context: CGContext, size: CGSize) {
    let fontSize = size.height * 0.16
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
      NSAttributedString.Key(kCTStrokeColorAttributeName as String): CGColor(gray: 0.1, alpha: 1),
      NSAttributedString.Key(kCTStrokeWidthAttributeName as String): -5.0,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, [])
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: size.width / 2 - bounds.midX, y: size.height * 0.06)
    CTLineDraw(line, context)
  }

  // MARK: Colours

  private static func bodyColor(for role: SheetRole) -> CGColor {
    switch role {
    case .walk: return CGColor(red: 0.2, green: 0.68, blue: 0.36, alpha: 1)
    case .point: return CGColor(red: 0.16, green: 0.6, blue: 0.5, alpha: 1)
    case .kick: return CGColor(red: 0.85, green: 0.3, blue: 0.2, alpha: 1)
    case .rescuer: return CGColor(red: 0.2, green: 0.45, blue: 0.9, alpha: 1)
    case .fly: return CGColor(red: 0.5, green: 0.3, blue: 0.85, alpha: 1)
    case .explosion: return CGColor(red: 1, green: 0.6, blue: 0.1, alpha: 1)
    }
  }

  private static func accentColor(for role: SheetRole) -> CGColor {
    switch role {
    case .rescuer: return CGColor(red: 0.95, green: 0.8, blue: 0.2, alpha: 1)
    default: return CGColor(red: 0.95, green: 0.35, blue: 0.55, alpha: 1)
    }
  }

  private static func stroke(from: CGPoint, to: CGPoint, in context: CGContext) {
    context.move(to: from)
    context.addLine(to: to)
    context.strokePath()
  }
}
