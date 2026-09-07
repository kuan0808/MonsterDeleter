import CoreGraphics
import Foundation

@testable import MonsterDeleterKit

/// Tiny bitmaps for the pack tests: solid-colour sheets written as PNG files.
enum TestImages {
  /// A sheet of `columns` x `rows` cells of `cell` pixels each, filled with one colour.
  static func sheet(columns: Int, rows: Int, cell: CGSize, gray: CGFloat) -> CGImage? {
    let width = Int(cell.width) * columns
    let height = Int(cell.height) * rows
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
    // A colour in the context's own space lands as exact bytes, so the tests can read it back.
    guard let color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [gray, gray, gray, 1]) else {
      return nil
    }
    context.setFillColor(color)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  /// A bitmap of `width` x `height` pixels whose gray level comes from `gray(x, y)`.
  static func bitmap(width: Int, height: Int, gray: (Int, Int) -> CGFloat) -> CGImage? {
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
    for y in 0..<height {
      for x in 0..<width {
        let level = gray(x, y)
        guard let color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [level, level, level, 1])
        else { return nil }
        context.setFillColor(color)
        context.fill(CGRect(x: x, y: y, width: 1, height: 1))
      }
    }
    return context.makeImage()
  }

  /// A solid-gray sheet PNG on disk.
  @discardableResult
  static func writeSheet(
    to url: URL,
    columns: Int = 5,
    rows: Int = 3,
    cell: CGSize = CGSize(width: 4, height: 6),
    gray: CGFloat = 0.5
  )
    throws -> CGImage
  {
    guard let image = sheet(columns: columns, rows: rows, cell: cell, gray: gray) else {
      throw CocoaError(.fileWriteUnknown)
    }
    try PNGFile.write(image, to: url)
    return image
  }

  /// The red channel of the first pixel, 0...255.
  static func firstRed(of image: CGImage) -> UInt8? {
    guard let data = image.dataProvider?.data as Data? else { return nil }
    return data.first
  }
}
