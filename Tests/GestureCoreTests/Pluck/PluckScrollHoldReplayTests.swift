import Testing
@testable import GestureCore

/// What the grid's scroll view is given, held off or on, through every way a
/// pinch goes and every order of its end words (`PluckEndReplayTests`), and
/// through Alex's clip of October 10: a pluck, its break-free, spawn, and
/// carry let go; then the card carried by its own grab handle; then pinches
/// on the same item, another, and empty grid space, each told as a scroll by
/// the rules, which the grid's scroll view didn't take.
///
/// The clip's status line said the scroll was on, and the replays agree:
/// after that sequence nothing in GestureKit's state holds the scroll, the
/// container, the watch, and the value given to the scroll view all on, as
/// they were on `main` too. What changed at the pluck was when the scroll
/// came back: from October 9, at the break-free, while the pinch that lifted
/// the item was still down carrying what spawned. A lift given back to the
/// scroll brought it back mid-pinch the same way. Before October 9 a pluck
/// brought it back as its drag ended, the pinch let go. So the scroll now
/// comes back only once the pinch that took it lets go
/// (`PluckHoldWatch.holdsTheScroll`), and these replays hold the rules to it.
@Suite struct PluckScrollHoldReplayTests {
    typealias Replay = PluckEndReplayTests

    /// When a course's pinch is let go: its end words begin at 1 s.
    static let letGoAt = 1.0

    /// The times the scroll view was given on again while the pinch that held
    /// it off was still down, before `letGoAt`, in `grid`.
    static func comesBackMidPinch(_ grid: PluckReplayGrid) -> [Double] {
        let letGo = grid.at(letGoAt)
        var heldOff = false
        var times: [Double] = []
        for change in grid.given {
            if change.heldOff {
                heldOff = true
            } else if heldOff, change.at < letGo {
                let (seconds, attoseconds) = (change.at - grid.start).components
                times.append(Double(seconds) + Double(attoseconds) / 1e18)
                heldOff = false
            }
        }
        return times
    }

    /// The grid after `course`, its pinch still down, at `tuning`.
    static func liveGrid(_ course: Replay.Course, tuning: PluckTuning) -> PluckReplayGrid {
        var grid = PluckReplayGrid(tuning: tuning)
        Replay.run(course, on: &grid)
        grid.advance(to: letGoAt - 0.01)
        return grid
    }

    // MARK: Mid-pinch

    /// However a pinch goes, the scroll view, once held off under its lift,
    /// is never given on again while the pinch is still down.
    @Test(arguments: Replay.Course.allCases)
    func theScrollNeverComesBackWhileThePinchThatTookItIsDown(_ course: Replay.Course) {
        let grid = Self.liveGrid(course, tuning: PluckTuning())
        #expect(Self.comesBackMidPinch(grid).isEmpty, "\(course.rawValue): the scroll view given on mid-pinch at \(Self.comesBackMidPinch(grid)) s:\n\(grid.log.joined(separator: "\n"))")
    }

    /// As from October 9 to 10, the tuning that brings the scroll back as the
    /// item settles gives the scroll view on mid-pinch at the break-free and
    /// at the give-back, and nowhere else.
    @Test(arguments: Replay.Course.allCases)
    func tunedToComeBackMidPinchItDidAtTheBreakFreeAndTheGiveBack(_ course: Replay.Course) {
        let grid = Self.liveGrid(course, tuning: PluckTuning(scrollComesBackMidPinch: true))
        let times = Self.comesBackMidPinch(grid)
        switch course {
        case .spawned:
            #expect(times == [0.5], "\(times)")
        case .givenBack, .givenBackAndScrolled:
            #expect(times == [0.35], "\(times)")
        case .liftedStill, .liftedMoved, .scrolled:
            #expect(times.isEmpty, "\(times)")
        }
    }

    /// Every order of every end word, each said or not, around every way a
    /// pinch goes: the scroll view is given on once the pinch is over, and
    /// held off at no next pinch's touch, as `PluckEndReplayTests` asks of
    /// the whole hold, which counts what the scroll view is given.
    @Test func theEndReplaysCountWhatTheScrollViewIsGiven() {
        var grid = PluckReplayGrid()
        Replay.run(.spawned, on: &grid)
        #expect(grid.scrollViewHeldOff)
        #expect(Replay.isHeld(grid))
    }

    // MARK: Alex's clip of October 10

    /// The words that end the pull's pinch as it's let go: the drag's end and
    /// its gesture state's reset, the press's end, and the tap, each said or
    /// not, in every order, with the drag's end or reset, or the tap, among
    /// them, as the clip's pull ended ("pull · 1.27 s").
    static var releases: [[Replay.Ending]] {
        Replay.orders(of: [.dragEnded, .dragCancelled, .pressEnded, .tapped])
            .filter { order in order.contains(.dragEnded) || order.contains(.dragCancelled) || order.contains(.tapped) }
    }

    /// What one replay of the clip found at each step.
    struct Clip {
        var heldOffDuringTheCarry: Bool
        var heldAfterTheRelease: Bool
        var heldAfterTheCardsCarry: Bool
        var heldAtEachNextTouch: [Bool]
        var scrollsTaken: [Bool]
        var alarms: [PluckHoldWatch<String>.Alarm]
        var disagreement: String?
        var log: [String]
    }

    /// The clip: item 98 lifted, broken free, its spawn carried, and let go
    /// by `release`; the card then carried by its own grab handle for 1.27 s,
    /// which tells the grid nothing; then a quick pinch on item 98, one on
    /// item 99, and one on empty grid space, each moving 15 pt down within a
    /// tenth of a second, told as a scroll, the scroll view taking it if it's
    /// given on as the pinch touches.
    static func replayTheClip(release: [Replay.Ending], tuning: PluckTuning = PluckTuning()) -> Clip {
        var grid = PluckReplayGrid(tuning: tuning)
        grid.press("98", down: true)
        grid.advance(to: 0.1)
        grid.drag("98", 16, 0, 0)
        grid.advance(to: 0.5)
        grid.drag("98", 60, 0, 0)
        var heldDuringTheCarry = true
        for step in 1...6 {
            grid.advance(to: 0.5 + Double(step) / 10)
            grid.drag("98", 60 + Double(step) * 40, Double(step) * 5, Double(step) * 8)
            heldDuringTheCarry = heldDuringTheCarry && grid.scrollViewHeldOff
        }
        var time = 1.27
        for ending in release {
            grid.advance(to: time)
            switch ending {
            case .dragEnded: grid.dragEnded("98")
            case .dragCancelled: grid.dragStopped("98")
            case .pressEnded: grid.press("98", down: false)
            case .tapped: grid.tap("98")
            case .scrollIdle: grid.scrollPhase(.idle)
            case .itemWent: grid.itemWent("98")
            }
            time += 0.01
        }
        let heldAfterTheRelease = Replay.isHeld(grid)
        // The card carried by its grab handle, in the space: nothing to the
        // grid.
        time += 1.27
        grid.advance(to: time)
        let heldAfterTheCardsCarry = Replay.isHeld(grid)
        var heldAtEachTouch: [Bool] = []
        var taken: [Bool] = []
        for item in ["98", "99", nil] as [String?] {
            time += 1
            grid.advance(to: time)
            let heldOff = grid.scrollViewHeldOff
            heldAtEachTouch.append(heldOff)
            if let item {
                grid.drag(item, 0, 15, 0)
                grid.press(item, down: true)
            }
            if !heldOff {
                grid.scrollPhase(.interacting)
                grid.scrollOffsetChanged(to: grid.scrollOffset + SIMD2(0, 60))
            }
            taken.append(!heldOff)
            grid.advance(to: time + 0.1)
            if let item {
                grid.press(item, down: false)
                grid.dragEnded(item)
                grid.dragStopped(item)
            }
            grid.advance(to: time + 0.5)
            if !heldOff { grid.scrollPhase(.idle) }
        }
        grid.advance(to: time + 2)
        return Clip(
            heldOffDuringTheCarry: heldDuringTheCarry,
            heldAfterTheRelease: heldAfterTheRelease,
            heldAfterTheCardsCarry: heldAfterTheCardsCarry,
            heldAtEachNextTouch: heldAtEachTouch,
            scrollsTaken: taken,
            alarms: grid.alarms,
            disagreement: grid.watch.disagreement,
            log: grid.log
        )
    }

    /// The clip, in every order of its release: the scroll held off through
    /// the carry and let go with the pinch; nothing held after it, nor after
    /// the card's carry; the scroll view given on at each next pinch's touch,
    /// taking each scroll; no views disagreeing, and no alarm.
    @Test func theClipLeavesNothingHeld() {
        for release in Self.releases {
            let clip = Self.replayTheClip(release: release)
            let spelled = String(release.map(\.rawValue))
            #expect(clip.heldOffDuringTheCarry, "\(spelled)")
            #expect(!clip.heldAfterTheRelease, "\(spelled)")
            #expect(!clip.heldAfterTheCardsCarry, "\(spelled)")
            #expect(clip.heldAtEachNextTouch == [false, false, false], "\(spelled)")
            #expect(clip.scrollsTaken == [true, true, true], "\(spelled)")
            #expect(clip.disagreement == nil, "\(spelled): \(clip.disagreement ?? "")")
            #expect(clip.alarms.isEmpty, "\(spelled): \(clip.alarms.map(\.line))\n\(clip.log.joined(separator: "\n"))")
        }
    }

    /// As on `main`, the scroll coming back mid-pinch at the break-free: its
    /// state after the clip is as right, nothing held, the scroll view given
    /// on at each next touch. GestureKit's state held nothing, as the status
    /// line said; only the scroll view, given on mid-pinch, didn't scroll.
    @Test func onMainTheClipsStateWasRightToo() {
        for release in Self.releases {
            let clip = Self.replayTheClip(release: release, tuning: PluckTuning(scrollComesBackMidPinch: true))
            let spelled = String(release.map(\.rawValue))
            #expect(!clip.heldOffDuringTheCarry, "\(spelled)")
            #expect(!clip.heldAfterTheCardsCarry, "\(spelled)")
            #expect(clip.heldAtEachNextTouch == [false, false, false], "\(spelled)")
        }
    }

    /// The pull's drag's end and reset both unheard after its carry, its
    /// tap too: the scroll stays held for its stale drag, and the next pinch
    /// on its item, within the net's three seconds, meets it held; that
    /// pinch's drag is taken as the carry's, its words ending it, and the
    /// pinches after scroll.
    @Test func aCarryWhoseEndWentUnheardHoldsTheScrollUntilAPinchEndsIt() {
        for release in [[], [Replay.Ending.pressEnded]] {
            let clip = Self.replayTheClip(release: release)
            #expect(clip.heldAfterTheRelease)
            #expect(clip.heldAfterTheCardsCarry)
            #expect(clip.heldAtEachNextTouch == [true, false, false])
            #expect(clip.scrollsTaken == [false, true, true])
        }
    }

    /// With nothing more said on the item after its carry's end went
    /// unheard, the safety net lets the scroll go three seconds after it was
    /// last heard from, raising the alarm.
    @Test func aCarryWhoseEndWentUnheardIsLetGoByTheNet() {
        var grid = PluckReplayGrid()
        Replay.run(.spawned, on: &grid)
        grid.advance(to: 0.6 + 3 - 0.01)
        #expect(grid.scrollViewHeldOff)
        grid.advance(to: 0.6 + 3 + 0.06)
        #expect(!grid.scrollViewHeldOff)
        #expect(grid.alarms.map(\.kind) == [.scrollLetGoWithNothingHeard])
    }
}
