/// One sound: a file name, its playback volume and whether it loops.
public struct AudioDescriptor: Codable, Sendable, Hashable {
  public var file: String
  public var volume: Double
  public var loops: Bool

  public init(file: String, volume: Double, loops: Bool = false) {
    self.file = file
    self.volume = volume
    self.loops = loops
  }
}
