import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing

@testable import MonsterDeleterKit

/// The packs under `Packaging/packs/` that `scripts/build-app.sh` copies into the bundle.
///
/// The fixtures elsewhere prove the loader against art written by the tests. This proves the art
/// that actually ships: a sheet that will not slice, a sound the manifest names but the folder does
/// not hold, or a frame index past the end of a sheet would otherwise reach a user with every
/// other suite green.
@Suite("Shipped packs")
struct ShippedPackTests {
  /// Every folder in `Packaging/packs/` with a `pack.json`, which is exactly what the build copies.
  static let folders: [URL] = {
    let packs = AppBundleTests.root.appending(path: "Packaging/packs")
    let contents = (try? FileManager.default.contentsOfDirectory(at: packs, includingPropertiesForKeys: nil)) ?? []
    return
      contents
      .filter { FileManager.default.fileExists(atPath: $0.appending(path: "pack.json").path) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }()

  let cache: SheetCache

  init() {
    cache = SheetCache(
      directory: FileManager.default.temporaryDirectory.appending(path: "ShippedPackTests-\(UUID().uuidString)")
    )
  }

  @Test("the build has built-in packs to copy")
  func present() {
    #expect(!Self.folders.isEmpty, "Packaging/packs holds no folder with a pack.json")
  }

  /// Cut on the grid the manifest declares, every frame the show plays has to carry paint. The
  /// explosion is the other way round: the app leaves its last frame up until the flight begins,
  /// so the sheet has to clear itself by then and paint may not come back once it has.
  @Test("every sheet is the pack's own and every frame it plays carries paint", arguments: folders)
  func sheets(folder: URL) throws {
    defer { try? FileManager.default.removeItem(at: cache.directory) }
    let pack = try FolderPack(folder: folder, cache: cache)
    #expect(pack.warnings.isEmpty, "\(folder.lastPathComponent): \(pack.warnings)")
    for role in SheetRole.allCases {
      let declared = try #require(pack.descriptor.sheets[role], "\(folder.lastPathComponent) \(role.rawValue)")
      let name = "\(folder.lastPathComponent) \(role.rawValue)"
      let file = folder.appending(path: declared.file)
      #expect(FileManager.default.fileExists(atPath: file.path), "\(name): \(declared.file) is not in the folder")
      let art = CGImageSourceCreateWithURL(file as CFURL, nil)
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
      if let art {
        #expect(
          art.width % declared.columns == 0 && art.height % declared.rows == 0,
          "\(name): \(art.width)x\(art.height) does not tile into \(declared.columns)x\(declared.rows)"
        )
      }
      let sheet = try pack.sheet(for: role)
      let frames = try #require(
        SheetSlicer.frames(of: sheet, columns: declared.columns, rows: declared.rows),
        "\(name): \(sheet.width)x\(sheet.height) will not cut into \(declared.columns)x\(declared.rows)"
      )
      #expect(frames.count == declared.frameCount, "\(name)")
      let painted = frames.map(Self.carriesPaint)
      #expect(painted.first == true, "\(name): the first frame is empty")
      guard role == .explosion else {
        #expect(!painted.contains(false), "\(name): frame \(painted.firstIndex(of: false) ?? 0) is empty")
        continue
      }
      let cleared = painted.firstIndex(of: false) ?? painted.count
      #expect(
        !painted[cleared...].contains(true),
        "\(name): paint comes back after the sheet clears on frame \(cleared)"
      )
      #expect(
        painted.last == false,
        "\(name): the last frame still carries paint, which the rescue holds on screen"
      )
    }
  }

  /// `MONSTER_AUTOPLAY_PACK` plays a shipped pack instead of the placeholder the self-test forces,
  /// and `AutoplaySelfTest` judges the run against `director.pack.choreography`, so a pack whose
  /// impact frame is its own has to move the timetable with it.
  @Test("a shipped pack's own frame indices drive the self-test timetable", arguments: folders)
  func timetableFollowsThePack(folder: URL) throws {
    defer { try? FileManager.default.removeItem(at: cache.directory) }
    let descriptor = try FolderPack(folder: folder, cache: cache).descriptor
    let choreography = Choreography(pack: descriptor)
    let timetable = ShowTimetable.confirmed(choreography, confirmDelay: .seconds(3))
    let impact = try #require(timetable.steps.first { $0.event == .entered(.exploding) })
    #expect(
      impact.after == choreography.frameDuration * descriptor.kickImpactFrame,
      "\(folder.lastPathComponent): the kick lands \(impact.after) in, not on frame \(descriptor.kickImpactFrame)"
    )
  }

  /// `ShowCheckpointTests` proves the six capture moments land inside their phases for
  /// `Choreography.standard`, which is the placeholder's. A pack moves those phase durations with
  /// it: `exploding` lasts `sheetDuration - impactDelay`, so a large enough `kickImpactFrame`
  /// leaves it shorter than the 4.5 frame slots the explosion checkpoint waits, and the capture
  /// would draw the rescue instead. Nothing would report that - `ShowStage.snapshot` renders
  /// whatever the layer tree holds - and a `MONSTER_AUTOPLAY_PACK` evidence run compares against
  /// no reference, so it would ship as a mislabelled capture.
  @Test("every checkpoint still lands inside its own phase under a shipped pack", arguments: folders)
  func checkpointsFitTheirPhases(folder: URL) throws {
    defer { try? FileManager.default.removeItem(at: cache.directory) }
    let choreography = Choreography(pack: try FolderPack(folder: folder, cache: cache).descriptor)
    for checkpoint in ShowCheckpoint.allCases {
      guard let duration = choreography.duration(of: checkpoint.phase) else { continue }
      #expect(
        checkpoint.offset(in: choreography) < duration,
        """
        \(folder.lastPathComponent): the \(checkpoint) checkpoint is \
        \(checkpoint.offset(in: choreography)) into a \(checkpoint.phase) phase that lasts \(duration)
        """
      )
    }
  }

  @Test("the frames the choreography names are inside the sheets that hold them", arguments: folders)
  func frameIndices(folder: URL) throws {
    defer { try? FileManager.default.removeItem(at: cache.directory) }
    let descriptor = try FolderPack(folder: folder, cache: cache).descriptor
    let kick = try #require(descriptor.sheets[.kick]).frameCount
    let point = try #require(descriptor.sheets[.point]).frameCount
    #expect(descriptor.kickImpactFrame < kick, "\(folder.lastPathComponent): impact frame past the kick sheet")
    #expect(descriptor.pointFrames.lowerBound >= 0, "\(folder.lastPathComponent): point frames start below zero")
    #expect(descriptor.pointFrames.upperBound < point, "\(folder.lastPathComponent): point frames past the sheet")
  }

  @Test("every sound is the pack's own and is a RIFF WAVE", arguments: folders)
  func sounds(folder: URL) throws {
    defer { try? FileManager.default.removeItem(at: cache.directory) }
    let pack = try FolderPack(folder: folder, cache: cache)
    for role in AudioRole.allCases {
      let declared = try #require(pack.descriptor.audio[role], "\(folder.lastPathComponent) \(role.rawValue)")
      #expect(
        FileManager.default.fileExists(atPath: folder.appending(path: declared.file).path),
        "\(folder.lastPathComponent) \(role.rawValue): \(declared.file) is not in the folder"
      )
      let data = try pack.audio(for: role)
      #expect(
        data.prefix(4).elementsEqual("RIFF".utf8) && data.dropFirst(8).prefix(4).elementsEqual("WAVE".utf8),
        "\(folder.lastPathComponent) \(role.rawValue) is not a RIFF WAVE"
      )
    }
  }

  /// The rescue takes the monster over from the kick's last frame, and the pack format carries no
  /// scale of its own for it: the art has to hand over at the size and the foot line the kick
  /// leaves. A rescuer clip framed further back drew the monster a third smaller the instant the
  /// rescue began, which reads as a pop rather than a rescue. Measured on the sliced frames at
  /// alpha >= 64, so it is the drawn silhouette and not the cell that is compared.
  @Test("the rescuer sheet takes the monster over at the kick's size and foot line", arguments: folders)
  func rescueHandover(folder: URL) throws {
    defer { try? FileManager.default.removeItem(at: cache.directory) }
    let pack = try FolderPack(folder: folder, cache: cache)
    let name = folder.lastPathComponent
    func frames(_ role: SheetRole) throws -> [CGImage] {
      let declared = try #require(pack.descriptor.sheets[role], "\(name) \(role.rawValue)")
      let sheet = try pack.sheet(for: role)
      return try #require(
        SheetSlicer.frames(of: sheet, columns: declared.columns, rows: declared.rows),
        "\(name) \(role.rawValue): will not cut"
      )
    }
    let lastKick = try #require(frames(.kick).last, "\(name): the kick sheet is empty")
    let firstRescue = try #require(frames(.rescuer).first, "\(name): the rescuer sheet is empty")
    let kick = try #require(Self.silhouette(lastKick), "\(name): the kick's last frame is blank")
    let rescue = try #require(Self.silhouette(firstRescue), "\(name): the rescuer's first frame is blank")
    #expect(
      rescue.height / kick.height >= 0.75,
      "\(name): the monster is \(rescue.height) of the rescuer's cell against \(kick.height) of the kick's"
    )
    #expect(
      abs(rescue.foot - kick.foot) <= 0.03,
      "\(name): the feet move from \(kick.foot) of the cell to \(rescue.foot) at the handover"
    )
  }

  /// A pack's tint replaces the ask bubble's paper, not its ink, so a dark one buries the question
  /// it is meant to carry. 4.5:1 is the WCAG AA threshold for the 16 pt text the bubble uses.
  @Test("the tint keeps the ask text readable against the ink", arguments: folders)
  func tintContrast(folder: URL) throws {
    defer { try? FileManager.default.removeItem(at: cache.directory) }
    let descriptor = try FolderPack(folder: folder, cache: cache).descriptor
    guard let tint = descriptor.tint else { return }
    let ink = try #require(NSColor(AskPalette.ink).usingColorSpace(.sRGB))
    let contrast = Self.contrast(
      Self.luminance(red: Double(tint.red) / 255, green: Double(tint.green) / 255, blue: Double(tint.blue) / 255),
      Self.luminance(red: ink.redComponent, green: ink.greenComponent, blue: ink.blueComponent)
    )
    #expect(contrast >= 4.5, "\(folder.lastPathComponent): tint \(tint.hex) reads at \(contrast):1")
  }

  /// A sheet whose backdrop never came off ships as a rectangle of paint behind the character: on
  /// screen the app draws the field, not just the figure, and the character wears a box. The
  /// corners are where that shows and where no pack's art belongs - every character sheet is drawn
  /// with its figure standing clear of them and every explosion has faded out by its own - so four
  /// pixels a frame catch the whole class for nothing.
  ///
  /// The bar is invisibility rather than zero: Kaiju's explosion carries alpha 7 in the corners of
  /// its first frames, which is the tail of a fading burst and draws nothing, while a sheet cut on
  /// a white field carries 255 there.
  ///
  /// The corners alone leave one sheet unguarded, so the frame's own painted bounding box is
  /// measured too: `pack-sheet.sh --inset F` draws each frame at F of the cell, centred, so an
  /// inset sheet's cell corners are structurally empty whatever the matte did - `packs/cat`'s
  /// explosion, cut at `--inset 0.85`, carries 18 px of margin left and right and 24 px top and
  /// bottom in every frame - and a field of paint drawn inside that inset rectangle would pass the
  /// corner check. A field is a filled rectangle and art never is, so the fraction of the bounding
  /// box's own border ring that is painted separates them: measured over all eighteen shipped
  /// sheets the worst frame anywhere is 0.196, most sheets sit under 0.12, and the same sheets
  /// composited onto white measure 1.000.
  ///
  /// Neither of those sees what the Cat pack actually shipped broken, which was the opposite of a
  /// field: a broad near-black surface came back from the matte at about half alpha, so the desktop
  /// showed through a band keyed out of the middle of a solid prop. That is an enclosed hole, so it
  /// is measured as one - over every 8-connected island of alpha < 200 that does not touch the
  /// frame's own border, the worst count of pixels in the half-alpha band, 64 <= alpha < 200. The
  /// worst island rather than the biggest one, so that a keyed hole cannot hide behind a larger
  /// neighbour in the same frame.
  ///
  /// Sliced as the app slices them, the rejected `packs/cat/rescuer.png` scores 2677 (frame 8, an
  /// island of 2,762 px) and the worst of all eighteen sheets as they ship is 303 (Kaiju's rescuer,
  /// frame 5), so 1000 sits 3.3x above the art and 2.7x below the defect. The band and not the
  /// island's area, because by area the defect is 2,762 against 1,242 for shipping art (`cat/walk`
  /// frame 8, a genuine gap between the cat's legs), only 2.2x: a gap in a silhouette reads at
  /// alpha 15-25 and a keyed surface at 134-150.
  ///
  /// This catches the enclosed form of the class only. The same commit's `cat/fly.png` scores 220,
  /// under Kaiju's own frames, because its keyed band ran out to the silhouette's edge instead of
  /// being enclosed. No measured alternative separates both: counting every half-alpha pixel more
  /// than 3 px inside the silhouette scores, on the raw sheets, the defect at 2338 and 326 but
  /// shipping art at 2010 (the UFO's tractor beam) and 20805 to 35368 (the explosion sheets' fading
  /// smoke). The rest of the class is held by the art rule in `AGENTS.md`: no broad near-black
  /// surface faces the backdrop.
  @Test("no shipped sheet is a field of paint: every frame's corners are transparent", arguments: folders)
  func cornersAreTransparent(folder: URL) throws {
    defer { try? FileManager.default.removeItem(at: cache.directory) }
    let pack = try FolderPack(folder: folder, cache: cache)
    for role in SheetRole.allCases {
      let declared = try #require(pack.descriptor.sheets[role], "\(folder.lastPathComponent) \(role.rawValue)")
      let name = "\(folder.lastPathComponent) \(role.rawValue)"
      let sheet = try pack.sheet(for: role)
      let frames = try #require(
        SheetSlicer.frames(of: sheet, columns: declared.columns, rows: declared.rows),
        "\(name): will not cut"
      )
      for (index, frame) in frames.enumerated() {
        let data = try #require(Self.pixels(of: frame), "\(name): frame \(index) will not be read")
        let corners = Self.cornerAlpha(data, width: frame.width, height: frame.height)
        #expect(
          corners.allSatisfy { $0 < 64 },
          "\(name): frame \(index) is painted into its corners (alpha \(corners)), so it ships on a field"
        )
        if let ring = Self.paintedBorderFill(data, width: frame.width, height: frame.height) {
          #expect(
            ring < 0.5,
            "\(name): frame \(index) fills \(ring) of its own painted border, so it ships on a field"
          )
        }
        let keyed = Self.keyedHole(data, width: frame.width, height: frame.height)
        #expect(
          keyed < 1000,
          """
          \(name): frame \(index) carries \(keyed) half-alpha pixels in one enclosed island, \
          so a surface came back from the matte half keyed out
          """
        )
      }
    }
  }

  /// `frame`'s pixels, premultiplied RGBA in rows of `frame.width * 4` bytes. A frame cut by
  /// `SheetSlicer` shares its sheet's pixel buffer, so it is drawn into a bitmap of its own to be
  /// read. `nil` when that bitmap cannot be made, which a caller has to carry rather than read as
  /// an answer: an empty buffer satisfies every threshold below vacuously.
  private static func pixels(of frame: CGImage) -> Data? {
    guard
      let context = CGContext(
        data: nil,
        width: frame.width,
        height: frame.height,
        bitsPerComponent: 8,
        bytesPerRow: frame.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
    return context.makeImage()?.dataProvider?.data as Data?
  }

  /// The alpha of the four corner pixels of a `width` by `height` frame's `data`, clockwise from
  /// the top left.
  private static func cornerAlpha(_ data: Data, width: Int, height: Int) -> [UInt8] {
    let last = width - 1
    let bottom = (height - 1) * width
    return [0, last, bottom + last, bottom].map { data[$0 * 4 + 3] }
  }

  /// How much of the painted bounding box's own border ring - its top and bottom rows and its
  /// first and last columns - is painted, at alpha >= 64. `nil` when the frame is blank or the
  /// box is under 3 px on a side, which has no ring worth measuring.
  private static func paintedBorderFill(_ data: Data, width: Int, height: Int) -> Double? {
    func painted(_ x: Int, _ y: Int) -> Bool { data[(y * width + x) * 4 + 3] >= 64 }
    var left = width, right = -1, top = height, bottom = -1
    for y in 0..<height {
      for x in 0..<width where painted(x, y) {
        left = min(left, x)
        right = max(right, x)
        top = min(top, y)
        bottom = max(bottom, y)
      }
    }
    guard right - left >= 2, bottom - top >= 2 else { return nil }
    var ring = 0
    var filled = 0
    for x in left...right {
      ring += 2
      filled += (painted(x, top) ? 1 : 0) + (painted(x, bottom) ? 1 : 0)
    }
    for y in (top + 1)..<bottom {
      ring += 2
      filled += (painted(left, y) ? 1 : 0) + (painted(right, y) ? 1 : 0)
    }
    return Double(filled) / Double(ring)
  }

  /// The most half-alpha pixels - 64 <= alpha < 200 - any one hole keyed through the middle of the
  /// frame carries: the worst 8-connected island of alpha < 200 that does not reach the frame's
  /// own border. Zero when nothing is enclosed.
  private static func keyedHole(_ data: Data, width: Int, height: Int) -> Int {
    var runs: [(row: Int, start: Int, end: Int, band: Int)] = []
    var parent: [Int] = []
    func root(of node: Int) -> Int {
      var node = node
      while parent[node] != node {
        parent[node] = parent[parent[node]]
        node = parent[node]
      }
      return node
    }
    var above: [Int] = []
    for y in 0..<height {
      var current: [Int] = []
      var x = 0
      while x < width {
        guard data[(y * width + x) * 4 + 3] < 200 else {
          x += 1
          continue
        }
        let start = x
        var band = 0
        while x < width, data[(y * width + x) * 4 + 3] < 200 {
          if data[(y * width + x) * 4 + 3] >= 64 { band += 1 }
          x += 1
        }
        runs.append((y, start, x, band))
        parent.append(runs.count - 1)
        current.append(runs.count - 1)
        for neighbour in above where runs[neighbour].start <= x && start <= runs[neighbour].end {
          let one = root(of: neighbour)
          let other = root(of: runs.count - 1)
          if one != other { parent[other] = one }
        }
      }
      above = current
    }
    var band = [Int](repeating: 0, count: runs.count)
    var reachesBorder = [Bool](repeating: false, count: runs.count)
    for (index, run) in runs.enumerated() {
      let island = root(of: index)
      band[island] += run.band
      if run.row == 0 || run.row == height - 1 || run.start == 0 || run.end == width {
        reachesBorder[island] = true
      }
    }
    var worst = 0
    for island in 0..<runs.count where root(of: island) == island && !reachesBorder[island] {
      worst = max(worst, band[island])
    }
    return worst
  }

  /// Whether any pixel of `frame` is not fully transparent.
  private static func carriesPaint(_ frame: CGImage) -> Bool {
    guard let data = pixels(of: frame) else { return false }
    return stride(from: 3, to: data.count, by: 4).contains { data[$0] > 0 }
  }

  /// The drawn silhouette of `frame`, as fractions of its own height: how tall the character is
  /// and where its lowest painted row sits. `nil` when nothing is painted. Alpha >= 64 is the
  /// threshold the pack evidence measures with, which ignores the matte's soft edge.
  private static func silhouette(_ frame: CGImage) -> (height: Double, foot: Double)? {
    guard let data = pixels(of: frame) else { return nil }
    let painted = (0..<frame.height).filter { row in
      let start = row * frame.width * 4
      return stride(from: start + 3, to: start + frame.width * 4, by: 4).contains { data[$0] >= 64 }
    }
    guard let first = painted.first, let last = painted.last else { return nil }
    return (Double(last - first) / Double(frame.height), Double(last) / Double(frame.height))
  }

  private static func luminance(red: Double, green: Double, blue: Double) -> Double {
    func linear(_ value: Double) -> Double {
      value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  private static func contrast(_ one: Double, _ other: Double) -> Double {
    (max(one, other) + 0.05) / (min(one, other) + 0.05)
  }
}
