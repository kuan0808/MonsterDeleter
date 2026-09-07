import Testing

@testable import MonsterDeleterKit

@Suite("LaunchDecision")
struct LaunchDecisionTests {
  @Test("the app window opens by itself until the introduction has been seen")
  func firstLaunch() {
    #expect(LaunchDecision(environment: [:], hasCompletedOnboarding: false).opensLandingWindow)
  }

  @Test("it never opens by itself once the introduction is done")
  func laterLaunch() {
    #expect(!LaunchDecision(environment: [:], hasCompletedOnboarding: true).opensLandingWindow)
  }

  @Test(
    "a self-test or an export run shows no window and wears no character",
    arguments: ["MONSTER_AUTOPLAY", "MONSTER_EXPORT_PLACEHOLDER"]
  )
  func headlessLaunch(variable: String) {
    let decision = LaunchDecision(environment: [variable: "/tmp/scratch"], hasCompletedOnboarding: false)
    #expect(decision.isHeadless)
    #expect(!decision.opensLandingWindow)
  }

  @Test("an empty variable is a real launch")
  func emptyVariable() {
    let environment = ["MONSTER_AUTOPLAY": "", "MONSTER_EXPORT_PLACEHOLDER": ""]
    let decision = LaunchDecision(environment: environment, hasCompletedOnboarding: false)
    #expect(!decision.isHeadless)
    #expect(decision.opensLandingWindow)
  }
}
