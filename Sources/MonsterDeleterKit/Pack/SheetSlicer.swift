import CoreGraphics

/// Cuts a sheet into frames, row-major from the top-left, as the original's `load_spritesheet` did.
public enum SheetSlicer {
  public static func frames(of sheet: CGImage, columns: Int, rows: Int) -> [CGImage]? {
    guard columns > 0, rows > 0 else { return nil }
    let width = sheet.width / columns
    let height = sheet.height / rows
    var frames: [CGImage] = []
    frames.reserveCapacity(columns * rows)
    for row in 0..<rows {
      for column in 0..<columns {
        let rect = CGRect(x: column * width, y: row * height, width: width, height: height)
        guard let frame = sheet.cropping(to: rect) else { return nil }
        frames.append(frame)
      }
    }
    return frames
  }
}
