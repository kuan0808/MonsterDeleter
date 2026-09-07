import Compression
import Foundation

/// Writes zip files byte by byte (stored entries, no compression), so the tests can build
/// archives `zip` would refuse to make, such as one with a `../` entry, or one whose headers
/// understate what a deflated entry really unpacks to.
enum TestZip {
  struct Entry {
    let name: String
    let data: Data
    /// Deflate the payload, so the declared size can differ from what unzip writes.
    var deflated = false
    /// The uncompressed size the headers declare; the payload's real size when nil.
    var declaredSize: UInt32?
  }

  static func write(_ entries: [(name: String, data: Data)], to url: URL) throws {
    try write(entries.map { Entry(name: $0.name, data: $0.data) }, to: url)
  }

  static func write(_ entries: [Entry], to url: URL) throws {
    var file = Data()
    var directory = Data()
    for entry in entries {
      let name = Data(entry.name.utf8)
      let crc = crc32(entry.data)
      let payload = entry.deflated ? deflate(entry.data) : entry.data
      let sizes = (
        method: UInt16(entry.deflated ? 8 : 0), compressed: UInt32(payload.count),
        uncompressed: entry.declaredSize ?? UInt32(entry.data.count)
      )
      let offset = UInt32(file.count)
      file.append(header(signature: 0x0403_4B50, crc: crc, sizes: sizes, name: name))
      file.append(payload)
      var central = Data()
      central.append(little(UInt32(0x0201_4B50)))
      central.append(little(UInt16(20)))
      central.append(header(signature: nil, crc: crc, sizes: sizes, name: name).dropLast(name.count))
      central.append(little(UInt16(0)))  // comment length
      central.append(little(UInt16(0)))  // disk
      central.append(little(UInt16(0)))  // internal attributes
      central.append(little(UInt32(0)))  // external attributes
      central.append(little(offset))
      central.append(name)
      directory.append(central)
    }
    let directoryOffset = UInt32(file.count)
    file.append(directory)
    file.append(little(UInt32(0x0605_4B50)))
    file.append(little(UInt16(0)))
    file.append(little(UInt16(0)))
    file.append(little(UInt16(entries.count)))
    file.append(little(UInt16(entries.count)))
    file.append(little(UInt32(directory.count)))
    file.append(little(directoryOffset))
    file.append(little(UInt16(0)))
    try file.write(to: url)
  }

  /// Raw DEFLATE, the payload shape zip's method 8 wants.
  private static func deflate(_ data: Data) -> Data {
    let capacity = data.count + 64 * 1024
    var output = Data(count: capacity)
    let written = output.withUnsafeMutableBytes { destination in
      data.withUnsafeBytes { source in
        guard let destination = destination.bindMemory(to: UInt8.self).baseAddress,
          let source = source.bindMemory(to: UInt8.self).baseAddress
        else { return 0 }
        return compression_encode_buffer(destination, capacity, source, data.count, nil, COMPRESSION_ZLIB)
      }
    }
    return output.prefix(written)
  }

  /// A local header (with its signature) or the shared tail of a central header (without one).
  private static func header(
    signature: UInt32?,
    crc: UInt32,
    sizes: (method: UInt16, compressed: UInt32, uncompressed: UInt32),
    name: Data
  ) -> Data {
    var data = Data()
    if let signature {
      data.append(little(signature))
    }
    data.append(little(UInt16(20)))  // version needed
    data.append(little(UInt16(0)))  // flags
    data.append(little(sizes.method))  // 0 stored, 8 deflated
    data.append(little(UInt16(0)))  // time
    data.append(little(UInt16(0x21)))  // date: 1980-01-01
    data.append(little(crc))
    data.append(little(sizes.compressed))
    data.append(little(sizes.uncompressed))
    data.append(little(UInt16(name.count)))
    data.append(little(UInt16(0)))  // extra length
    data.append(name)
    return data
  }

  private static func little<T: FixedWidthInteger>(_ value: T) -> Data {
    var little = value.littleEndian
    return Swift.withUnsafeBytes(of: &little) { Data($0) }
  }

  private static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
      }
    }
    return ~crc
  }
}
