import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

/// The slicing cache: a pack's sheets scaled once so every frame is twice its displayed height,
/// kept as small PNGs under Application Support. The show reads those and never decodes the
/// original sheets (the upstream explosion is 7200 x 5760). An entry is keyed by the sheet file's
/// modification date, its grid and the frame height, so editing the sheet or `pack.json`
/// replaces it. A cache that cannot be written only costs the next launch a decode.
public struct SheetCache: Sendable {
  public let directory: URL
  private let logger = Logger(subsystem: "io.github.kuan0808.MonsterDeleter", category: "pack")

  public init(directory: URL) {
    self.directory = directory
  }

  /// `file` scaled so each of its `columns` x `rows` frames is `frameHeight` pixels tall, from
  /// the cache when the file has not changed since it was written.
  public func sheet(for role: SheetRole, at file: URL, columns: Int, rows: Int, frameHeight: Int) throws -> CGImage {
    guard columns > 0, rows > 0, frameHeight > 0 else { throw PackError.cannotSlice(role) }
    // FileManager reads the date fresh; URL.resourceValues would hand back a cached one.
    guard let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    else { throw PackError.cannotDecode(file.lastPathComponent) }
    let stamp = Int64((modified.timeIntervalSince1970 * 1000).rounded())
    let entry = directory.appending(path: "\(role.rawValue)-\(stamp)-\(columns)x\(rows)-\(frameHeight).png")
    if let cached = Self.decode(entry) {
      return cached
    }
    guard let source = Self.decode(file) else { throw PackError.cannotDecode(file.lastPathComponent) }
    guard let scaled = Self.scale(source, columns: columns, rows: rows, frameHeight: frameHeight) else {
      throw PackError.cannotSlice(role)
    }
    store(scaled, at: entry, role: role)
    return scaled
  }

  // MARK: Scaling

  /// Draws the sheet's grid (any remainder pixels dropped) into a bitmap whose cells are exactly
  /// `frameHeight` tall, so `SheetSlicer` cuts it at the same cell boundaries.
  private static func scale(_ sheet: CGImage, columns: Int, rows: Int, frameHeight: Int) -> CGImage? {
    let cellWidth = sheet.width / columns
    let cellHeight = sheet.height / rows
    guard cellWidth > 0, cellHeight > 0 else { return nil }
    let frameWidth = max(1, Int((Double(cellWidth) * Double(frameHeight) / Double(cellHeight)).rounded()))
    let width = frameWidth * columns
    let height = frameHeight * rows
    guard let grid = sheet.cropping(to: CGRect(x: 0, y: 0, width: cellWidth * columns, height: cellHeight * rows)),
      let context = bitmapContext(width: width, height: height)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(grid, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  // MARK: Files

  /// A fully decoded bitmap of a PNG or other image file, or `nil`.
  private static func decode(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let context = bitmapContext(width: image.width, height: image.height)
    else { return nil }
    // Core Animation would otherwise decode the file again for every cropped frame.
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
  }

  private func store(_ image: CGImage, at entry: URL, role: SheetRole) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let temporary = directory.appending(path: ".\(entry.lastPathComponent).\(UUID().uuidString)")
      guard
        let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil)
      else { throw CocoaError(.fileWriteUnknown) }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
      _ = try FileManager.default.replaceItemAt(entry, withItemAt: temporary)
      evictStaleEntries(for: role, keeping: entry)
    } catch {
      logger.warning(
        "Cannot cache \(role.rawValue, privacy: .public) sheet: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func evictStaleEntries(for role: SheetRole, keeping entry: URL) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
    for name in names where name.hasPrefix("\(role.rawValue)-") && name != entry.lastPathComponent {
      try? FileManager.default.removeItem(at: directory.appending(path: name))
    }
  }

  private static func bitmapContext(width: Int, height: Int) -> CGContext? {
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  }
}
