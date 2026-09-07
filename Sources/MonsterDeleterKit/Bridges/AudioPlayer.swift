import AVFoundation
import os

/// AVFoundation bridge. SwiftUI has no audio playback API, so per-track volume and a looping
/// background bed have to come from AVFoundation. Three `AVAudioPlayer`s prepared once per pack
/// with the pack's volumes; the background track loops until the show ends. macOS needs no audio
/// session.
@MainActor
public final class AudioPlayer {
  private var players: [AudioRole: AVAudioPlayer] = [:]
  private let logger = Logger(subsystem: "io.github.kuan0808.MonsterDeleter", category: "audio")

  public init(pack: LoadedPack) {
    for role in AudioRole.allCases {
      guard let data = pack.audio[role], let descriptor = pack.descriptor.audio[role] else { continue }
      do {
        let player = try AVAudioPlayer(data: data)
        player.volume = Float(descriptor.volume)
        player.numberOfLoops = descriptor.loops ? -1 : 0
        player.prepareToPlay()
        players[role] = player
      } catch {
        logger.error(
          "Cannot prepare \(role.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  public func play(_ role: AudioRole) {
    guard let player = players[role] else { return }
    player.currentTime = 0
    player.play()
  }

  public func stopAll() {
    for player in players.values {
      player.stop()
    }
  }
}
