import Foundation
import Testing

@testable import MonsterDeleterKit

@Suite("ShowMachine")
struct ShowMachineTests {
  let target = CGPoint(x: 1000, y: 500)

  func machine(target: CGPoint?, count: Int = 1) -> (ManualClock, ShowMachine<ManualClock>) {
    let clock = ManualClock()
    return (clock, ShowMachine(choreography: .standard, clock: clock, target: target, targetCount: count))
  }

  @Test("a selection of any size runs the one timeline: one walk, one ask, one kick", arguments: [1, 2, 5, 12])
  func selectionSize(count: Int) {
    var (clock, machine) = machine(target: target, count: count)
    #expect(machine.targetCount == count)
    #expect(machine.start() == [.entered(.walking)])
    clock.advance(by: .milliseconds(4500))
    #expect(machine.tick() == [.entered(.asking)])
    clock.advance(by: .milliseconds(500))
    #expect(machine.tick() == [.askBubbleDue])
    #expect(machine.confirm() == [.entered(.kicking)])
    clock.advance(by: .milliseconds(625))
    #expect(machine.tick() == [.entered(.exploding)], "every item explodes on the one impact frame")
    clock.advance(by: .milliseconds(5125))
    #expect(machine.tick() == [.entered(.rescuing), .entered(.flying), .entered(.done)])
    #expect(machine.targetCount == count)
  }

  @Test("a known target walks straight in and plays the whole timeline")
  func happyPath() {
    var (clock, machine) = machine(target: target)
    #expect(machine.start() == [.entered(.walking)])
    #expect(machine.target == target)
    #expect(!machine.isInteractive)

    clock.advance(by: .milliseconds(4499))
    #expect(machine.tick().isEmpty)
    clock.advance(by: .milliseconds(1))
    #expect(machine.tick() == [.entered(.asking)])
    #expect(machine.isInteractive)

    clock.advance(by: .milliseconds(499))
    #expect(machine.tick().isEmpty)
    clock.advance(by: .milliseconds(1))
    #expect(machine.tick() == [.askBubbleDue])

    clock.advance(by: .seconds(30))
    #expect(machine.tick().isEmpty, "asking waits for the user")
    #expect(machine.phase == .asking)

    #expect(machine.confirm() == [.entered(.kicking)])
    #expect(!machine.isInteractive)
    clock.advance(by: .milliseconds(625))
    #expect(machine.tick() == [.entered(.exploding)])
    clock.advance(by: .milliseconds(1250))
    #expect(machine.tick() == [.entered(.rescuing)])
    clock.advance(by: .milliseconds(1875))
    #expect(machine.tick() == [.entered(.flying)])
    clock.advance(by: .milliseconds(2000))
    #expect(machine.tick() == [.entered(.done)])

    clock.advance(by: .seconds(5))
    #expect(machine.tick().isEmpty)
    #expect(machine.phase == .done)
  }

  @Test("without a target the show aims first, then fades the backdrop for 500 ms")
  func aimingPath() {
    var (clock, machine) = machine(target: nil)
    #expect(machine.start() == [.entered(.aiming)])
    #expect(machine.isInteractive)
    #expect(machine.nextDeadline == nil)

    clock.advance(by: .seconds(3))
    #expect(machine.tick().isEmpty)

    #expect(machine.aim(at: target) == [.entered(.entering)])
    #expect(machine.target == target)
    #expect(!machine.isInteractive)
    clock.advance(by: .milliseconds(499))
    #expect(machine.tick().isEmpty)
    clock.advance(by: .milliseconds(1))
    #expect(machine.tick() == [.entered(.walking)])
  }

  @Test("a late tick crosses every due phase in order")
  func lateTick() {
    var (clock, machine) = machine(target: target)
    _ = machine.start()
    clock.advance(by: .seconds(60))
    #expect(machine.tick() == [.entered(.asking), .askBubbleDue])
    _ = machine.confirm()
    clock.advance(by: .seconds(60))
    #expect(machine.tick() == [.entered(.exploding), .entered(.rescuing), .entered(.flying), .entered(.done)])
  }

  @Test("late ticks do not drift the schedule")
  func noDrift() {
    var (clock, machine) = machine(target: target)
    _ = machine.start()
    clock.advance(by: .milliseconds(4600))
    #expect(machine.tick() == [.entered(.asking)])
    clock.advance(by: .milliseconds(400))
    #expect(machine.tick() == [.askBubbleDue], "the bubble is due 500 ms after the scheduled start of asking")
  }

  @Test("cancel from aiming ends the show untouched")
  func cancelWhileAiming() {
    var (_, machine) = machine(target: nil)
    _ = machine.start()
    #expect(machine.cancel() == [.entered(.cancelled)])
    #expect(machine.phase == .cancelled)
    #expect(machine.aim(at: target).isEmpty)
    #expect(machine.tick().isEmpty)
  }

  @Test("cancel from asking ends the show and nothing explodes afterwards")
  func cancelWhileAsking() {
    var (clock, machine) = machine(target: target)
    _ = machine.start()
    clock.advance(by: .seconds(5))
    _ = machine.tick()
    #expect(machine.phase == .asking)
    #expect(machine.cancel() == [.entered(.cancelled)])
    #expect(machine.confirm().isEmpty)
    clock.advance(by: .seconds(60))
    #expect(machine.tick().isEmpty)
    #expect(machine.phase == .cancelled)
    #expect(machine.nextDeadline == nil)
  }

  @Test(
    "cancel is ignored during click-through phases",
    arguments: [Duration.seconds(1), .milliseconds(5100), .milliseconds(6000), .milliseconds(8000)]
  )
  func cancelIgnoredWhileClickThrough(offset: Duration) {
    var (clock, machine) = machine(target: target)
    _ = machine.start()
    clock.advance(by: .seconds(5))
    _ = machine.tick()
    _ = machine.confirm()
    clock.advance(by: offset)
    _ = machine.tick()
    let before = machine.phase
    #expect(!before.isInteractive)
    #expect(machine.cancel().isEmpty)
    #expect(machine.phase == before)
  }

  @Test("confirm and aim are ignored outside their phases")
  func inputsIgnoredOutsidePhase() {
    var (clock, machine) = machine(target: target)
    _ = machine.start()
    #expect(machine.confirm().isEmpty)
    #expect(machine.aim(at: target).isEmpty)
    #expect(machine.phase == .walking)
    clock.advance(by: .seconds(5))
    _ = machine.tick()
    #expect(machine.aim(at: target).isEmpty)
    #expect(machine.phase == .asking)
  }

  @Test("nothing happens before start")
  func beforeStart() {
    var (clock, machine) = machine(target: target)
    clock.advance(by: .seconds(60))
    #expect(machine.tick().isEmpty)
    #expect(machine.confirm().isEmpty)
    #expect(machine.cancel().isEmpty)
    #expect(machine.phase == .walking)
  }

  @Test("the next deadline follows the timing table")
  func deadlines() {
    var (clock, machine) = machine(target: target)
    _ = machine.start()
    #expect(machine.nextDeadline == clock.now.advanced(by: .milliseconds(4500)))
    clock.advance(by: .milliseconds(4500))
    _ = machine.tick()
    #expect(machine.nextDeadline == clock.now.advanced(by: .milliseconds(500)), "asking still owes the bubble")
    clock.advance(by: .milliseconds(500))
    _ = machine.tick()
    #expect(machine.nextDeadline == nil, "asking waits for the user")
    _ = machine.confirm()
    #expect(machine.nextDeadline == clock.now.advanced(by: .milliseconds(625)))
  }

  @Test("interactivity per phase follows plan decision 7", arguments: ShowPhase.allCases)
  func interactivity(phase: ShowPhase) {
    #expect(phase.isInteractive == (phase == .aiming || phase == .asking))
  }

  @Test(
    "cancel is ignored while entering and walking, the click-through phases before the ask",
    arguments: [Duration.milliseconds(100), .milliseconds(499)]
  )
  func cancelIgnoredBeforeAsk(offset: Duration) {
    var (clock, machine) = machine(target: nil)
    _ = machine.start()
    _ = machine.aim(at: target)
    clock.advance(by: offset)
    _ = machine.tick()
    #expect(machine.phase == .entering)
    #expect(machine.cancel().isEmpty)
    clock.advance(by: .seconds(1))
    _ = machine.tick()
    #expect(machine.phase == .walking)
    #expect(machine.cancel().isEmpty)
    #expect(machine.phase == .walking)
  }

  @Test("time in the phase restarts at every transition, timed or not")
  func elapsedInPhase() {
    var (clock, machine) = machine(target: nil)
    _ = machine.start()
    clock.advance(by: .seconds(3))
    #expect(machine.elapsedInPhase == .seconds(3))
    _ = machine.aim(at: target)
    #expect(machine.elapsedInPhase == .zero)
    clock.advance(by: .milliseconds(5700))
    _ = machine.tick()
    #expect(machine.phase == .asking)
    #expect(machine.elapsedInPhase == .milliseconds(700), "measured from the scheduled start of asking, not the tick")
    _ = machine.confirm()
    #expect(machine.elapsedInPhase == .zero)
  }

  @Test("a confirm before the bubble is due skips the bubble")
  func confirmBeforeBubble() {
    var (clock, machine) = machine(target: target)
    _ = machine.start()
    clock.advance(by: .milliseconds(4600))
    #expect(machine.tick() == [.entered(.asking)])
    #expect(machine.confirm() == [.entered(.kicking)])
    clock.advance(by: .seconds(60))
    #expect(!machine.tick().contains(.askBubbleDue))
  }

  @Test(
    "a swap during the ask never touches the machine: any pause leaves the phase, target and timing alone",
    arguments: [Duration.zero, .milliseconds(1500), .seconds(30), .seconds(600)]
  )
  func swapShapedPause(pause: Duration) {
    var (clock, machine) = machine(target: target, count: 3)
    _ = machine.start()
    clock.advance(by: .seconds(5))
    #expect(machine.tick() == [.entered(.asking), .askBubbleDue])
    clock.advance(by: pause)
    #expect(machine.tick().isEmpty)
    #expect(machine.phase == .asking)
    #expect(machine.target == target)
    #expect(machine.targetCount == 3)
    #expect(machine.nextDeadline == nil)
    #expect(machine.confirm() == [.entered(.kicking)])
    clock.advance(by: .milliseconds(624))
    #expect(machine.tick().isEmpty)
    clock.advance(by: .milliseconds(1))
    #expect(machine.tick() == [.entered(.exploding)], "the impact comes 625 ms after the confirm, whatever the pause")
  }

  @Test("any selection size from one to two thousand plays the one timeline and ends done")
  func anySelectionSize() {
    for count in 1...2000 {
      var (clock, machine) = machine(target: target, count: count)
      #expect(machine.start() == [.entered(.walking)])
      clock.advance(by: .seconds(5))
      #expect(machine.tick() == [.entered(.asking), .askBubbleDue])
      #expect(machine.confirm() == [.entered(.kicking)])
      clock.advance(by: .milliseconds(5750))
      #expect(machine.tick() == [.entered(.exploding), .entered(.rescuing), .entered(.flying), .entered(.done)])
      #expect(machine.targetCount == count)
    }
  }

  @Test("the timed phases chain in the show's order and stop at the phases that wait or end")
  func successorChain() {
    var chain: [ShowPhase] = [.entering]
    while let next = chain[chain.count - 1].successor {
      chain.append(next)
    }
    #expect(chain == [.entering, .walking, .asking], "the walk ends at the ask, which waits for the user")
    chain = [.kicking]
    while let next = chain[chain.count - 1].successor {
      chain.append(next)
    }
    #expect(chain == [.kicking, .exploding, .rescuing, .flying, .done])
    #expect(ShowPhase.aiming.successor == nil)
    #expect(ShowPhase.cancelled.successor == nil)
    #expect(ShowPhase.allCases.filter(\.isTerminal) == [.done, .cancelled])
  }
}
