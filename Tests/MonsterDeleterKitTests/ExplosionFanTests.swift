import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("ExplosionFan")
struct ExplosionFanTests {
  let center = CGPoint(x: 1000, y: 540)

  @Test("one item explodes on the target point itself")
  func single() {
    #expect(ExplosionFan.centers(around: center, count: 1, radius: 75) == [center])
  }

  @Test("no items, no explosions")
  func none() {
    #expect(ExplosionFan.centers(around: center, count: 0, radius: 75).isEmpty)
  }

  @Test("two hits sit either side of the point")
  func pair() {
    let centers = ExplosionFan.centers(around: center, count: 2, radius: 75)
    #expect(centers == [CGPoint(x: 1075, y: 540), CGPoint(x: 925, y: 540)])
  }

  @Test("up to six hits ring the point evenly, starting at the right and going counterclockwise")
  func ringOnly() {
    let centers = ExplosionFan.centers(around: center, count: 3, radius: 75)
    #expect(centers == [CGPoint(x: 1075, y: 540), CGPoint(x: 962, y: 605), CGPoint(x: 962, y: 475)])
  }

  @Test("from seven hits on, the point itself is hit and the first ring holds six")
  func centerAndFirstRing() {
    let centers = ExplosionFan.centers(around: center, count: 7, radius: 75)
    #expect(
      centers == [
        CGPoint(x: 1000, y: 540),
        CGPoint(x: 1075, y: 540),
        CGPoint(x: 1038, y: 605),
        CGPoint(x: 962, y: 605),
        CGPoint(x: 925, y: 540),
        CGPoint(x: 962, y: 475),
        CGPoint(x: 1038, y: 475),
      ]
    )
  }

  @Test("twelve hits fill the centre, the first ring and five of the second at twice the radius")
  func secondRing() {
    let centers = ExplosionFan.centers(around: center, count: 12, radius: 75)
    #expect(centers.count == 12)
    #expect(Set(centers.map { "\($0.x),\($0.y)" }).count == 12, "no two hits share a point")
    #expect(centers[0] == center)
    for point in centers[1...6] {
      let distance = hypot(point.x - center.x, point.y - center.y)
      #expect(abs(distance - 75) <= 1, "\(point) should sit 75 pt out")
    }
    let outer = centers[7...]
    #expect(outer.count == 5)
    for point in outer {
      let distance = hypot(point.x - center.x, point.y - center.y)
      #expect(abs(distance - 150) <= 1, "\(point) should sit 150 pt out")
    }
  }

  @Test("hit counts", arguments: [1, 2, 5, 12, 19])
  func counts(count: Int) {
    #expect(ExplosionFan.centers(around: center, count: count, radius: 75).count == count)
  }

  @Test("a big selection draws no more than the centre and two rings", arguments: [20, 40, 2000])
  func cappedHits(count: Int) {
    let centers = ExplosionFan.centers(around: center, count: count, radius: 75)
    #expect(centers.count == ExplosionFan.maxHits)
    #expect(centers == ExplosionFan.centers(around: center, count: 19, radius: 75))
  }
}
