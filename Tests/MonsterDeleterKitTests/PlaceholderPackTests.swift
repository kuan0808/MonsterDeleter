import CoreGraphics
import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("PlaceholderPack")
struct PlaceholderPackTests {
  @Test("every sheet slices into 15 frames of the declared size")
  func slicesEverySheet() throws {
    let pack = try LoadedPack(source: PlaceholderPack())
    for role in SheetRole.allCases {
      let frames = pack.frames(for: role)
      #expect(frames.count == 15, "\(role)")
      let expected =
        role == .explosion ? PlaceholderSheetRenderer.explosionFrameSize : PlaceholderSheetRenderer.characterFrameSize
      #expect(
        frames.allSatisfy { CGFloat($0.width) == expected.width && CGFloat($0.height) == expected.height },
        "\(role)"
      )
    }
    #expect(pack.aspect(of: .walk) == 0.5625)
    #expect(pack.aspect(of: .explosion) == 0.75)
    #expect(pack.choreography == .standard)
  }

  @Test("frames are cut row-major from the top-left")
  func rowMajorSlicing() throws {
    let width = 5
    let height = 3
    let context = try #require(
      CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    // Paint the top-left pixel red; Core Graphics is bottom-up so that is y = 2.
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 2, width: 1, height: 1))
    let sheet = try #require(context.makeImage())
    let frames = try #require(SheetSlicer.frames(of: sheet, columns: 5, rows: 3))
    #expect(frames.count == 15)
    #expect(frames.allSatisfy { $0.width == 1 && $0.height == 1 })
    #expect(alpha(of: frames[0]) == 255, "frame 0 is the top-left cell")
    #expect(alpha(of: frames[14]) == 0, "frame 14 is the bottom-right cell")
  }

  @Test("sounds are canonical 16-bit mono WAV data")
  func wavData() throws {
    let pack = try LoadedPack(source: PlaceholderPack())
    for role in AudioRole.allCases {
      let data = try #require(pack.audio[role])
      #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF", "\(role)")
      #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE", "\(role)")
      #expect((data.count - 44) % 2 == 0, "\(role)")
    }
    #expect(try #require(pack.audio[.bgm]).count == 44 + 16 * 11_025 * 2, "sixteen quarter-second notes at 44.1 kHz")
  }

  private func alpha(of image: CGImage) -> UInt8? {
    guard let data = image.dataProvider?.data as Data? else { return nil }
    return data.last
  }
}
