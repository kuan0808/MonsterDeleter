import Foundation

/// `MONSTER_AUTOPLAY=<path>[:<path>...]` runs one show on launch without a Finder, checks it
/// against the choreography's timetable and quits with a non-zero status on any miss: the
/// self-test (`scripts/self-test.sh`). Several colon-separated paths make one selection (paths
/// with a colon in them are not supported here).
///
/// - `MONSTER_AUTOPLAY_POINT=x,y` aims at that AppKit global point (default: main screen centre).
/// - `MONSTER_AUTOPLAY_CONFIRM_DELAY=<seconds>` answers that long after the bubble appears
///   (default 2).
/// - `MONSTER_AUTOPLAY_ANSWER=esc` presses Esc instead of the button, so the show must end
///   cancelled with the selection untouched.
/// - `MONSTER_AUTOPLAY_PACK=<pack id>` plays the show in that pack (`PackEntry.id`, for instance
///   `builtIn/kaiju`) instead of the placeholder the self-test otherwise forces, for capturing a
///   pack's own evidence. An id the library does not hold ends the run.
/// - `MONSTER_AUTOPLAY_SNAPSHOTS=<folder>` writes one PNG per checkpoint (`ShowCheckpoint`).
/// - `MONSTER_AUTOPLAY_REFERENCE=<folder>` compares every checkpoint against the PNG of the same
///   name in that folder and fails the self-test on a mismatch.
/// - `MONSTER_AUTOPLAY_SHOWS=<n>` plays the show that many times in one process, recreating the
///   scratch items a confirmed show trashed, and prints the memory footprint after each show.
public struct AutoplayOptions: Sendable, Hashable {
  /// How the autoplay answers the ask.
  public enum Answer: String, Sendable, Hashable {
    case confirm
    case escape = "esc"
  }

  /// The selection, sorted like the Services path sorts it.
  public var targets: [URL]
  public var point: CGPoint?
  public var confirmDelay: Duration
  public var answer: Answer
  /// The pack the show wears, or `nil` for the placeholder the self-test forces.
  public var packID: String?
  public var snapshotDirectory: URL?
  public var referenceDirectory: URL?
  /// How many shows to play in one process; at least one.
  public var shows: Int

  public init(
    targets: [URL],
    point: CGPoint?,
    confirmDelay: Duration,
    answer: Answer = .confirm,
    packID: String? = nil,
    snapshotDirectory: URL? = nil,
    referenceDirectory: URL? = nil,
    shows: Int = 1
  ) {
    self.targets = targets
    self.point = point
    self.confirmDelay = confirmDelay
    self.answer = answer
    self.packID = packID
    self.snapshotDirectory = snapshotDirectory
    self.referenceDirectory = referenceDirectory
    self.shows = max(shows, 1)
  }

  public init?(environment: [String: String]) {
    let paths = (environment["MONSTER_AUTOPLAY"] ?? "").split(separator: ":").filter { !$0.isEmpty }
    guard !paths.isEmpty else { return nil }
    targets = SelectionOrder.sorted(paths.map { URL(fileURLWithPath: String($0)) })
    point = environment["MONSTER_AUTOPLAY_POINT"].flatMap(Self.parsePoint)
    confirmDelay = environment["MONSTER_AUTOPLAY_CONFIRM_DELAY"].flatMap(Self.parseDelay) ?? .seconds(2)
    answer = environment["MONSTER_AUTOPLAY_ANSWER"].flatMap(Answer.init(rawValue:)) ?? .confirm
    packID = environment["MONSTER_AUTOPLAY_PACK"].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap {
      $0.isEmpty ? nil : $0
    }
    snapshotDirectory = environment["MONSTER_AUTOPLAY_SNAPSHOTS"].flatMap(Self.parseFolder)
    referenceDirectory = environment["MONSTER_AUTOPLAY_REFERENCE"].flatMap(Self.parseFolder)
    shows = max(environment["MONSTER_AUTOPLAY_SHOWS"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1, 1)
  }

  private static func parsePoint(_ text: String) -> CGPoint? {
    let parts = text.split(separator: ",")
    guard parts.count == 2,
      let x = Double(parts[0].trimmingCharacters(in: .whitespaces)), x.isFinite,
      let y = Double(parts[1].trimmingCharacters(in: .whitespaces)), y.isFinite
    else { return nil }
    return CGPoint(x: x, y: y)
  }

  private static func parseDelay(_ text: String) -> Duration? {
    guard let seconds = Double(text.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds >= 0 else {
      return nil
    }
    return .seconds(seconds)
  }

  private static func parseFolder(_ text: String) -> URL? {
    text.isEmpty ? nil : URL(fileURLWithPath: text, isDirectory: true)
  }
}
