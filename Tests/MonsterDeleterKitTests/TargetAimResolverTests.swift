import Foundation
import Testing

@testable import MonsterDeleterKit

/// Stands in for Finder's accessibility tree, the one system boundary of the accessibility tier,
/// so no test here talks to the real Finder.
struct StubIconRects: IconRectSource {
  var rects: [URL: CGRect] = [:]
  /// How long the stub takes to answer. `Task.sleep` gives up the moment the budget cancels it,
  /// which is the contract every source has to honour.
  var takes: Duration = .zero

  func iconRects(for urls: [URL]) async -> [URL: CGRect] {
    if takes > .zero {
      do { try await Task.sleep(for: takes) } catch { return [:] }
    }
    return rects.filter { urls.contains($0.key) }
  }
}

/// A Finder that will not be interrupted: a synchronous accessibility message to a wedged Finder
/// runs to its own messaging timeout however early the reader is cancelled. This one answers
/// only when the test releases it, so "the show did not wait for the read" is a fact about the
/// order of events rather than a wall-clock measurement.
actor HeldIconRects: IconRectSource {
  private let rects: [URL: CGRect]
  private var waiting: CheckedContinuation<Void, Never>?
  private var released = false

  init(rects: [URL: CGRect]) { self.rects = rects }

  func iconRects(for urls: [URL]) async -> [URL: CGRect] {
    if !released {
      await withCheckedContinuation { waiting = $0 }
    }
    return rects.filter { urls.contains($0.key) }
  }

  /// Lets the held read finish, so no test leaves a continuation behind.
  func release() {
    released = true
    waiting?.resume()
    waiting = nil
  }
}

@Suite("Target aim resolver")
struct TargetAimResolverTests {
  let now = ContinuousClock.now
  let click = CGPoint(x: 1584, y: 211)
  let alpha = URL(fileURLWithPath: "/tmp/alpha.txt")
  let bravo = URL(fileURLWithPath: "/tmp/bravo.txt")
  let charlie = URL(fileURLWithPath: "/tmp/charlie.txt")

  /// A 64 pt icon whose centre is (1000, 800) in AppKit global coordinates.
  let alphaIcon = CGRect(x: 968, y: 768, width: 64, height: 64)
  let bravoIcon = CGRect(x: 1080, y: 768, width: 64, height: 64)

  /// The arrangement the coordinate tests use: the 1x main screen, and the 2x screen with a
  /// negative origin below it.
  let mainScreen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
  let secondScreen = CGRect(x: 1239, y: -982, width: 1512, height: 982)
  /// A 64 pt icon on the second screen, centred on (1532, -268).
  let charlieIcon = CGRect(x: 1500, y: -300, width: 64, height: 64)

  var freshSample: TargetSample { TargetSample(point: click, takenAt: now.advanced(by: .seconds(-2))) }

  func aim(
    _ urls: [URL],
    sample: TargetSample?,
    icons: (any IconRectSource)?,
    screens: [CGRect] = [],
    budget: Duration = .milliseconds(50)
  ) async -> TargetAim? {
    await TargetAimResolver.aim(
      for: urls,
      sample: sample,
      now: now,
      icons: icons,
      screens: screens,
      budget: budget
    )
  }

  @Test("with the permission off the show aims at the right-click")
  func permissionOff() async {
    let aim = await aim([alpha], sample: freshSample, icons: nil)
    #expect(aim == TargetAim(point: click))
  }

  @Test("a resolver that finds nothing leaves the right-click standing")
  func resolverFindsNothing() async {
    let aim = await aim([alpha], sample: freshSample, icons: StubIconRects())
    #expect(aim == TargetAim(point: click))
  }

  @Test("one resolved icon becomes the target point")
  func oneIcon() async {
    let aim = await aim([alpha], sample: freshSample, icons: StubIconRects(rects: [alpha: alphaIcon]))
    #expect(aim?.point == CGPoint(x: 1000, y: 800))
    #expect(aim?.iconRects == [alphaIcon])
  }

  @Test("an icon outranks the right-click, and also stands in for a missing one")
  func iconOutranksTheClick() async {
    let icons = StubIconRects(rects: [alpha: alphaIcon])
    #expect(await aim([alpha], sample: nil, icons: icons)?.point == CGPoint(x: 1000, y: 800))
  }

  @Test("the icons that resolved keep the selection's order and the rest fan around the click")
  func subsetOfASelection() async {
    let icons = StubIconRects(rects: [bravo: bravoIcon, alpha: alphaIcon])
    let aim = await aim([alpha, bravo, charlie], sample: freshSample, icons: icons)
    #expect(aim?.iconRects == [alphaIcon, bravoIcon])
    #expect(aim?.point == CGPoint(x: 1056, y: 800), "the icons' union, centred")
    #expect(aim?.fanCenter == click)
  }

  @Test("with no right-click behind them the unresolved targets fan around the icons")
  func subsetWithoutAClick() async {
    let icons = StubIconRects(rects: [alpha: alphaIcon])
    let aim = await aim([alpha, bravo], sample: nil, icons: icons)
    #expect(aim?.fanCenter == CGPoint(x: 1000, y: 800))
  }

  /// The read holds an icon the aim would have used, so an aim that waited for it would carry
  /// that icon: the right-click coming back is what says the budget abandoned the read.
  @Test("a resolver that overruns its budget is abandoned for the right-click", .timeLimit(.minutes(1)))
  func budgetOverrun() async {
    let icons = StubIconRects(rects: [alpha: alphaIcon], takes: .seconds(10))
    let aim = await aim([alpha], sample: freshSample, icons: icons, budget: .milliseconds(50))
    #expect(aim == TargetAim(point: click))
  }

  /// The read is released only once the aim is in hand, so an aim that waited for it could not
  /// arrive at all and fails as a hung test. Nothing is measured against the wall clock here:
  /// on a loaded machine that measures the machine, not the budget.
  @Test(
    "a read that cannot be interrupted still costs the show no more than its budget",
    .timeLimit(.minutes(1))
  )
  func budgetBoundsAnUninterruptibleRead() async {
    let icons = HeldIconRects(rects: [alpha: alphaIcon])
    let aim = await aim([alpha], sample: freshSample, icons: icons, budget: .milliseconds(50))
    #expect(aim == TargetAim(point: click))
    await icons.release()
  }

  @Test("a stale right-click and no icon means the crosshair")
  func nothingToAimAt() async {
    let stale = TargetSample(point: click, takenAt: now.advanced(by: .seconds(-16)))
    #expect(await aim([alpha], sample: stale, icons: StubIconRects()) == nil)
    #expect(await aim([alpha], sample: nil, icons: nil) == nil)
  }

  @Test("an empty selection has nothing to aim at")
  func emptySelection() async {
    #expect(await aim([], sample: freshSample, icons: StubIconRects()) == TargetAim(point: click))
  }

  /// A show runs on one screen's panel, so an icon on another display cannot be exploded where
  /// it sits: those targets join the fan instead.
  @Test("a selection straddling two displays keeps the icons of the right-click's screen")
  func selectionStraddlingTwoDisplays() async {
    let icons = StubIconRects(rects: [alpha: alphaIcon, charlie: charlieIcon])
    let aim = await aim(
      [alpha, charlie],
      sample: freshSample,
      icons: icons,
      screens: [mainScreen, secondScreen]
    )
    #expect(aim?.iconRects == [alphaIcon], "the click is on the main screen")
    #expect(aim?.point == CGPoint(x: 1000, y: 800))
    #expect(aim?.fanCenter == click)

    let layout = Choreography.standard.layout(
      aim: aim ?? TargetAim(point: click),
      targetCount: 2,
      screen: mainScreen,
      characterAspect: 0.5625,
      explosionAspect: 0.75
    )
    #expect(
      layout.explosionCenters == [CGPoint(x: 1000, y: 800), CGPoint(x: click.x, y: click.y + 40)],
      "the kept icon explodes on itself and the other display's target is fanned"
    )
  }

  @Test("the one icon that resolved is dropped when it is on another display than the right-click")
  func loneIconOnAnotherDisplay() async {
    let icons = StubIconRects(rects: [charlie: charlieIcon])
    let aim = await aim(
      [alpha, charlie],
      sample: freshSample,
      icons: icons,
      screens: [mainScreen, secondScreen]
    )
    #expect(aim == TargetAim(point: click), "both targets fan around the right-click")
    #expect(aim?.iconRects.isEmpty == true)
  }

  @Test("a lone icon on another display still stands when there is no right-click to place")
  func loneIconWithoutAClick() async {
    let icons = StubIconRects(rects: [charlie: charlieIcon])
    let aim = await aim([alpha, charlie], sample: nil, icons: icons, screens: [mainScreen, secondScreen])
    #expect(aim?.iconRects == [charlieIcon])
  }

  @Test("with no right-click behind it the screen holding the most icons wins")
  func busiestScreenWins() async {
    let icons = StubIconRects(rects: [alpha: alphaIcon, bravo: bravoIcon, charlie: charlieIcon])
    let aim = await aim(
      [alpha, bravo, charlie],
      sample: nil,
      icons: icons,
      screens: [secondScreen, mainScreen]
    )
    #expect(aim?.iconRects == [alphaIcon, bravoIcon])
    #expect(aim?.fanCenter == aim?.point, "the fan has no click to gather around")
  }

  @Test("without any screen frames every resolved icon is kept")
  func noScreenInformation() async {
    let icons = StubIconRects(rects: [alpha: alphaIcon, charlie: charlieIcon])
    let aim = await aim([alpha, charlie], sample: freshSample, icons: icons)
    #expect(aim?.iconRects == [alphaIcon, charlieIcon])
  }
}
