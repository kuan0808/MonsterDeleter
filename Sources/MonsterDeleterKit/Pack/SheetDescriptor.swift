/// One sprite sheet: a file name and its grid. Frames are numbered row-major from the top-left.
public struct SheetDescriptor: Codable, Sendable, Hashable {
  public static let standardColumns = 5
  public static let standardRows = 3
  public static let standardFrameCount = standardColumns * standardRows

  public var file: String
  public var columns: Int
  public var rows: Int

  public init(file: String, columns: Int = Self.standardColumns, rows: Int = Self.standardRows) {
    self.file = file
    self.columns = columns
    self.rows = rows
  }

  public var frameCount: Int { columns * rows }
}
