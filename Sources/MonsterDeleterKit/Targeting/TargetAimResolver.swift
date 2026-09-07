import Foundation

/// Picks the aim of one show from the three tiers of the plan (section 6.4), best first:
///
/// 1. the icons Finder draws for the selection, read from its accessibility tree,
/// 2. the last right-click, which lands on the icon or its label in every Finder view,
/// 3. the crosshair, when neither of the two above answered.
///
/// Every step falls silently to the one below it, per target where it can: a selection whose
/// icons resolve one by one keeps the ones it got and fans the rest around the right-click. The
/// accessibility tier is bounded by `budget`, so a busy Finder costs the show that long at
/// worst and never more.
///
/// The screen frames are a parameter rather than something read here: this type stays pure, so
/// the tests can lay out any arrangement of displays without one.
public enum TargetAimResolver {
  /// What the whole accessibility tier gets before the show goes on without it. The measured
  /// app-side cost of one resolution on macOS 26 is 42 to 91 ms, a column view with nine columns
  /// being the slowest (`docs/adr/0005-accessibility-target-tier.md`); this clears the slowest of those by
  /// about 60 ms, so an ordinary Finder always answers and a stuck one is dropped long before
  /// anybody notices.
  public static let budget: Duration = .milliseconds(150)

  public static func aim(
    for urls: [URL],
    sample: TargetSample?,
    now: ContinuousClock.Instant,
    icons: (any IconRectSource)?,
    screens: [CGRect] = [],
    budget: Duration = budget
  ) async -> TargetAim? {
    let click = TargetPointResolver.resolve(sample, now: now)
    guard let icons, !urls.isEmpty else { return click.map { TargetAim(point: $0) } }

    let rects = await withinBudget(budget) { await icons.iconRects(for: urls) }
    let resolved = urls.compactMap { rects[$0] }
    let aimed = onOneScreen(resolved, screens: screens, click: click)
    guard let first = aimed.first else { return click.map { TargetAim(point: $0) } }

    let bounds = aimed.dropFirst().reduce(first) { $0.union($1) }
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    return TargetAim(point: center, iconRects: aimed, fanCenter: click ?? center)
  }

  /// The icons of one screen. A show runs on one screen's panel, so an icon on another display
  /// could not be exploded where it sits anyway: it would be clamped to the edge of the panel's
  /// screen, far from the file. Those targets are dropped here instead and fanned around the
  /// fan centre, exactly as a target the tier could not resolve at all already is.
  ///
  /// The screen is the one the right-click is on, since that is the screen the user is working
  /// on, and otherwise the one holding the most icons, the first of the given order breaking a
  /// tie. One icon is held to the same rule as any larger set, so an icon alone on another
  /// display falls to the right-click rather than dragging the whole show over to it. Without
  /// any screen frames there is nothing to divide the icons by, so they all stay.
  private static func onOneScreen(_ rects: [CGRect], screens: [CGRect], click: CGPoint?) -> [CGRect] {
    guard !screens.isEmpty else { return rects }
    func holds(_ screen: CGRect, _ rect: CGRect) -> Bool {
      screen.contains(CGPoint(x: rect.midX, y: rect.midY))
    }
    let clicked = click.flatMap { point in screens.first { $0.contains(point) } }
    let busiest = screens.max { left, right in
      rects.count(where: { holds(left, $0) }) < rects.count(where: { holds(right, $0) })
    }
    guard let screen = clicked ?? busiest else { return rects }
    return rects.filter { holds(screen, $0) }
  }

  /// Runs `read` against the clock and answers with whichever of the two arrives first, so the
  /// budget is the whole wait and not the budget plus one outstanding accessibility message.
  ///
  /// The read is unstructured on purpose: a task group waits for every child it holds, so a
  /// cancelled read that is inside a synchronous message to a wedged Finder would keep the show
  /// waiting for that message. Here the budget returns at once and the abandoned read stops on
  /// its own cancellation, which is why `IconRectSource` promises to honour one.
  private static func withinBudget(
    _ budget: Duration,
    _ read: @escaping @Sendable () async -> [URL: CGRect]
  ) async -> [URL: CGRect] {
    let (answers, answer) = AsyncStream<[URL: CGRect]>.makeStream()
    let reader = Task { answer.yield(await read()) }
    let deadline = Task {
      try? await Task.sleep(for: budget)
      answer.yield([:])
    }
    defer {
      reader.cancel()
      deadline.cancel()
    }
    var first = answers.makeAsyncIterator()
    return await first.next() ?? [:]
  }
}
