import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("Onboarding")
@MainActor
struct OnboardingTests {
  let defaults: UserDefaults

  init() throws {
    defaults = try #require(UserDefaults(suiteName: "OnboardingTests-\(UUID().uuidString)"))
  }

  @Test("a fresh install has seen nothing")
  func freshInstall() {
    let onboarding = Onboarding(defaults: defaults)
    #expect(!onboarding.isCompleted)
    #expect(!onboarding.hasSummonedFromFinder)
    #expect(!onboarding.sawUnaimedFan)
  }

  @Test("finishing the introduction survives a relaunch, and asking for it again undoes that")
  func completionPersists() {
    let onboarding = Onboarding(defaults: defaults)
    onboarding.complete()
    #expect(Onboarding(defaults: defaults).isCompleted)
    onboarding.restart()
    #expect(!Onboarding(defaults: defaults).isCompleted)
  }

  @Test("the first summon from Finder is remembered, so the step that teaches it can say so")
  func summonFromFinder() {
    let onboarding = Onboarding(defaults: defaults)
    onboarding.recordSummonFromFinder()
    #expect(onboarding.hasSummonedFromFinder)
    #expect(Onboarding(defaults: defaults).hasSummonedFromFinder)
  }

  @Test("a ring of explosions offers icon aiming, and dismissing it lasts until the next ring")
  func aimingTip() {
    let onboarding = Onboarding(defaults: defaults)
    onboarding.recordUnaimedFan()
    #expect(onboarding.sawUnaimedFan)
    onboarding.dismissAimingTip()
    #expect(!onboarding.sawUnaimedFan)
    onboarding.recordUnaimedFan()
    #expect(onboarding.sawUnaimedFan, "a later ring may offer it again")
  }
}
