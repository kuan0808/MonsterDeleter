import CoreGraphics

/// How far two checkpoint captures are apart: the share of pixels whose colour differs.
public enum SnapshotComparison {
  /// Pixels that differ by more than this much in one channel (0...255) count as different;
  /// resampling and antialiasing noise stays below it.
  public static let defaultThreshold: UInt8 = 40

  /// The share (0...1) of pixels where any channel differs by more than `threshold`, or `nil`
  /// when the images are not the same size.
  public static func mismatch(_ a: CGImage, _ b: CGImage, threshold: UInt8 = defaultThreshold) -> Double? {
    guard a.width == b.width, a.height == b.height, a.width > 0, a.height > 0 else { return nil }
    guard let bytesA = rgba(a), let bytesB = rgba(b) else { return nil }
    var differing = 0
    let limit = Int(threshold)
    for pixel in stride(from: 0, to: bytesA.count, by: 4) {
      for channel in pixel..<pixel + 4 where abs(Int(bytesA[channel]) - Int(bytesB[channel])) > limit {
        differing += 1
        break
      }
    }
    return Double(differing) / Double(a.width * a.height)
  }

  /// The image as 8-bit premultiplied RGBA, whatever it was stored as.
  private static func rgba(_ image: CGImage) -> [UInt8]? {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: image.width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    return drawn ? bytes : nil
  }
}
