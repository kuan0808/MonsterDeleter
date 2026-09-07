import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("SelectionOrder")
struct SelectionOrderTests {
  @Test("Finder's scrambled selection comes out in name order")
  func sortsByName() {
    let urls = ["/tmp/sel/5.txt", "/tmp/sel/folder", "/tmp/sel/2.txt"].map { URL(fileURLWithPath: $0) }
    let sorted = SelectionOrder.sorted(urls).map(\.lastPathComponent)
    #expect(sorted == ["2.txt", "5.txt", "folder"])
  }

  @Test("numeric runs compare by value and case is ignored, like Finder")
  func finderLikeOrdering() {
    let urls = ["/a/file10.txt", "/a/File2.txt", "/a/beta", "/a/Alpha"].map { URL(fileURLWithPath: $0) }
    let sorted = SelectionOrder.sorted(urls).map(\.lastPathComponent)
    #expect(sorted == ["Alpha", "beta", "File2.txt", "file10.txt"])
  }

  @Test("every permutation of a selection comes out in the same order")
  func deterministic() {
    let paths = ["/sel/b.txt", "/sel/A.txt", "/sel/folder", "/sel/10.txt", "/sel/9.txt"]
    let expected = ["9.txt", "10.txt", "A.txt", "b.txt", "folder"]
    for shift in paths.indices {
      let rotated = Array(paths[shift...] + paths[..<shift]).map { URL(fileURLWithPath: $0) }
      #expect(SelectionOrder.sorted(rotated).map(\.lastPathComponent) == expected)
      #expect(SelectionOrder.sorted(rotated.reversed()).map(\.lastPathComponent) == expected)
    }
  }

  @Test("an empty selection stays empty")
  func empty() {
    #expect(SelectionOrder.sorted([]).isEmpty)
  }
}
