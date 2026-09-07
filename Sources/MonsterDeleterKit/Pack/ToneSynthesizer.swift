import Foundation

/// Generates the placeholder pack's sounds as 16-bit mono WAV data, deterministically.
public enum ToneSynthesizer {
  public static let sampleRate = 44_100

  /// A four second arpeggio loop; stands in for the background music.
  public static func backgroundLoop() -> Data {
    let notes: [Double] = [261.63, 329.63, 392.0, 523.25, 392.0, 329.63, 293.66, 349.23]
    let noteSeconds = 0.25
    var samples: [Float] = []
    for pass in 0..<2 {
      for (index, base) in notes.enumerated() {
        let frequency = pass == 1 && index >= 4 ? base * 1.5 : base
        samples += tone(frequency: frequency, seconds: noteSeconds, attack: 0.02, release: 0.1, amplitude: 0.35)
      }
    }
    return wav(samples)
  }

  /// A short rising chirp; stands in for the monster's line.
  public static func voice() -> Data {
    let seconds = 0.45
    let count = Int(seconds * Double(sampleRate))
    var samples: [Float] = []
    samples.reserveCapacity(count)
    var phase = 0.0
    for i in 0..<count {
      let t = Double(i) / Double(count)
      let frequency = 380 + 320 * t
      phase += 2 * .pi * frequency / Double(sampleRate)
      let envelope = min(t / 0.05, 1) * min((1 - t) / 0.2, 1)
      samples.append(Float(sin(phase) * envelope * 0.6))
    }
    return wav(samples)
  }

  /// A decaying noise burst over a low thump; stands in for the explosion.
  public static func explosion() -> Data {
    let seconds = 0.9
    let count = Int(seconds * Double(sampleRate))
    var samples: [Float] = []
    samples.reserveCapacity(count)
    var noiseState: UInt32 = 0x1234_5678
    for i in 0..<count {
      let t = Double(i) / Double(sampleRate)
      noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
      let noise = Double(noiseState >> 8) / Double(1 << 24) * 2 - 1
      let decay = exp(-t * 5)
      let thump = sin(2 * .pi * 55 * t) * exp(-t * 8)
      samples.append(Float((noise * 0.6 + thump * 0.8) * decay))
    }
    return wav(samples)
  }

  static func tone(frequency: Double, seconds: Double, attack: Double, release: Double, amplitude: Double) -> [Float] {
    let count = Int(seconds * Double(sampleRate))
    var samples: [Float] = []
    samples.reserveCapacity(count)
    for i in 0..<count {
      let t = Double(i) / Double(sampleRate)
      let envelope = min(t / attack, 1) * min((seconds - t) / release, 1)
      // Sine plus a quieter octave for a little body.
      let value = sin(2 * .pi * frequency * t) + 0.3 * sin(4 * .pi * frequency * t)
      samples.append(Float(value * envelope * amplitude))
    }
    return samples
  }

  /// Wraps samples in a canonical 44-byte WAV header (PCM, mono, 16-bit).
  static func wav(_ samples: [Float]) -> Data {
    let dataSize = UInt32(samples.count * 2)
    var data = Data()
    data.reserveCapacity(44 + Int(dataSize))
    data.append(ascii: "RIFF")
    data.append(littleEndian: 36 + dataSize)
    data.append(ascii: "WAVE")
    data.append(ascii: "fmt ")
    data.append(littleEndian: UInt32(16))
    data.append(littleEndian: UInt16(1))
    data.append(littleEndian: UInt16(1))
    data.append(littleEndian: UInt32(sampleRate))
    data.append(littleEndian: UInt32(sampleRate * 2))
    data.append(littleEndian: UInt16(2))
    data.append(littleEndian: UInt16(16))
    data.append(ascii: "data")
    data.append(littleEndian: dataSize)
    for sample in samples {
      let clamped = max(-1, min(1, sample))
      data.append(littleEndian: UInt16(bitPattern: Int16(clamped * 32_767)))
    }
    return data
  }
}

extension Data {
  fileprivate mutating func append(ascii: String) {
    append(contentsOf: Array(ascii.utf8))
  }

  fileprivate mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
    var little = value.littleEndian
    Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
  }
}
