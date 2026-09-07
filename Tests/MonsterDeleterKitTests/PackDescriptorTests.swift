import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("PackDescriptor")
struct PackDescriptorTests {
  @Test("the placeholder declares all six sheets and three sounds with the original's volumes")
  func placeholderContents() {
    let pack = PackDescriptor.placeholder
    #expect(Set(pack.sheets.keys) == Set(SheetRole.allCases))
    #expect(Set(pack.audio.keys) == Set(AudioRole.allCases))
    #expect(pack.audio[.bgm]?.volume == 0.5)
    #expect(pack.audio[.bgm]?.loops == true)
    #expect(pack.audio[.voice]?.volume == 1.0)
    #expect(pack.audio[.explosion]?.volume == 0.3)
    #expect(pack.sheets[.explosion]?.frameCount == 15)
  }

  @Test("the placeholder is the defaults with a name and a description")
  func placeholderIsNamedDefaults() {
    var named = PackDescriptor.defaults
    named.name = PackDescriptor.placeholder.name
    named.description = PackDescriptor.placeholder.description
    #expect(named == .placeholder)
    #expect(PackDescriptor.defaults.name.isEmpty)
  }

  @Test(
    "default frame indices follow the grid",
    arguments: [(15, 11...14, 5), (6, 2...5, 5), (4, 0...3, 3), (1, 0...0, 0)]
  )
  func defaultFrameIndices(frameCount: Int, pointFrames: ClosedRange<Int>, impact: Int) {
    #expect(PackDescriptor.defaultPointFrames(frameCount: frameCount) == pointFrames)
    #expect(PackDescriptor.defaultKickImpactFrame(frameCount: frameCount) == impact)
  }
}
