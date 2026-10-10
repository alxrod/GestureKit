import Testing
@testable import GestureCore

/// Every order of the words that end a pinch on a pluckable item, each said
/// or not, replayed through the grid as the adapter wires it
/// (`PluckReplayGrid`), around each way a pinch goes: a lift with no spawn,
/// still or moved; a break-free, its spawn, and the carry; a lift given back
/// to the scroll, which the scroll view takes up or doesn't; and a pinch
/// that becomes a scroll before its hold. Then the next pinch begins, on the
/// same item, another, or the grid's empty space, and tries to scroll.
///
/// Once the pinch is over, nothing may hold the container's scroll or stay
/// lifted, so the next pinch, wherever it lands, meets the scroll on: at
/// once, or once the quiet after its last word has passed, should its words
/// say so; and whatever words go unheard.
///
/// Before the fix, the replays failed exactly where the words that say a
/// lifted pinch is let go never came, or never could:
///
/// - **A lift kept up past its press, with no tap.** Its press ended, as the
///   lift's stop of the scroll may cancel it, with its drag silent, and no
///   tap came, as none comes for a cancelled press: `P`, `PS` on a still
///   lift. Nothing was left to say it was let go, so it waited for the next
///   pinch on an item, which settled it at its own touch, too late for that
///   pinch to scroll, since its scroll view met the scroll off as it
///   touched; a pinch on the grid's empty space never settled it.
/// - **A tap while the press, or the drag, still had the pinch**, its end
///   unheard: `T`, `TS`, on a still lift, and with the drag's end and
///   cancel unheard, `PT`, `PST` after a move or a spawn. The tap settled
///   only a lift neither gesture had, and a pinch on another item settled
///   only a lift kept up past its press, so it stayed past every pinch but
///   one on the same item.
/// - **No word at all from a gesture that had the pinch**: `none`, `S`, and,
///   after a move or a spawn, `P` and `PS` with the drag's end and cancel
///   unheard. A press on the same item joined the pinch the stale drag
///   "had", moving its spawn, and a pinch elsewhere left it alone.
///
/// The alarm (`PluckHoldWatch`) was raised in exactly those replays.
///
/// The rules now take each word for what it says: a lift kept up past its
/// press is let go once nothing has been heard for the quiet
/// (`PluckTuning.quietRelease`); the tap is the pinch let go, whatever its
/// gestures still say; a press on the item, or a pinch elsewhere, ends a
/// pinch whose gestures went quiet, their ends unheard; and breaking free
/// settles the item, so a carry never holds the scroll. So the scroll goes
/// once the words say the pinch is over, in every order, at once but for the
/// quiet; where no word comes at all from a gesture that had the pinch, the
/// container's safety net lets its hold go a second after it last heard from
/// it (`PluckTuning.unheardHoldRelease`), and raises the alarm, the only
/// replays that do.
@Suite struct PluckEndReplayTests {
    /// How a pinch went before the words that end it.
    enum Course: String, CaseIterable, CustomTestStringConvertible {
        /// Held still a quarter second: the item lifted, the hand still, the
        /// drag silent.
        case liftedStill
        /// Lifted, the drag having spoken, held short of breaking free.
        case liftedMoved
        /// Lifted, broken free, its spawn carried.
        case spawned
        /// Lifted, then given back to the scroll by a move along it, which
        /// the scroll view doesn't take up.
        case givenBack
        /// Given back, and the scroll view takes it up and scrolls.
        case givenBackAndScrolled
        /// Moved along the scroll before its hold, which the scroll view
        /// takes: a scroll.
        case scrolled

        var testDescription: String { rawValue }

        /// Whether the drag spoke, so its end or its cancel can come.
        var dragSpoke: Bool { self != .liftedStill }
    }

    /// A word that ends a pinch, said or not, in any order.
    enum Ending: Character, CaseIterable {
        /// The drag's `onEnded`.
        case dragEnded = "D"
        /// The drag's gesture state going false, a cancel should the drag
        /// still have the pinch.
        case dragCancelled = "C"
        /// The button's press going up, let go or cancelled.
        case pressEnded = "P"
        /// The button's tap.
        case tapped = "T"
        /// The scroll view's phase going to rest.
        case scrollIdle = "S"
        /// The item leaving the container.
        case itemWent = "G"
    }

    /// Where the next pinch lands.
    enum Next: String, CaseIterable, CustomTestStringConvertible {
        case sameItem
        case otherItem
        case emptySpace

        var testDescription: String { rawValue }
    }

    /// What one replay found.
    struct Outcome {
        /// The words said, in order.
        var endings: [Ending]
        /// Held or lifted once the pinch's words were said and the quiet
        /// after them passed.
        var heldOnceOver: Bool
        /// The scroll held as the next pinch touched, so it couldn't scroll.
        var heldAtNextTouch: Bool
        /// Held or lifted once the next pinch was over too.
        var heldAfterNext: Bool
        /// Held or lifted right after the pinch's words, before any quiet.
        var heldAfterWords: Bool
        /// Whether the watch raised its alarm before the next pinch.
        var alarmed: Bool
        /// Whether the safety net let the hold go before the next pinch.
        var netLetGo: Bool
        var log: [String]

        var failed: Bool { heldOnceOver || heldAtNextTouch || heldAfterNext }
        var spelled: String { endings.isEmpty ? "none" : String(endings.map(\.rawValue)) }
    }

    /// How long after a pinch's last word the replay waits before the next
    /// pinch: past any quiet the rules may wait for.
    static let quiet = 2.0

    // MARK: The courses

    /// Runs `course` on item "a", from its touch at 0.
    static func run(_ course: Course, on grid: inout PluckReplayGrid) {
        grid.press("a", down: true)
        switch course {
        case .liftedStill:
            grid.advance(to: 0.3)
        case .liftedMoved:
            grid.advance(to: 0.1)
            grid.drag("a", 16, 0, 0)
            grid.advance(to: 0.35)
            grid.drag("a", 30, 0, 0)
            grid.advance(to: 0.4)
        case .spawned:
            grid.advance(to: 0.1)
            grid.drag("a", 16, 0, 0)
            grid.advance(to: 0.5)
            grid.drag("a", 60, 0, 0)
            grid.advance(to: 0.6)
            grid.drag("a", 120, 10, 0)
        case .givenBack, .givenBackAndScrolled:
            grid.advance(to: 0.35)
            grid.drag("a", 0, 15, 0)
            grid.advance(to: 0.4)
            grid.drag("a", 0, 40, 0)
            if course == .givenBackAndScrolled {
                grid.scrollPhase(.interacting)
                grid.scrollOffsetChanged(to: SIMD2(0, 30))
            }
        case .scrolled:
            grid.advance(to: 0.1)
            grid.drag("a", 0, 15, 0)
            grid.scrollPhase(.interacting)
            grid.scrollOffsetChanged(to: SIMD2(0, 20))
            grid.advance(to: 0.4)
        }
    }

    /// Says `ending` to item "a".
    static func say(_ ending: Ending, on grid: inout PluckReplayGrid) {
        switch ending {
        case .dragEnded: grid.dragEnded("a")
        case .dragCancelled: grid.dragStopped("a")
        case .pressEnded: grid.press("a", down: false)
        case .tapped: grid.tap("a")
        case .scrollIdle: grid.scrollPhase(.idle)
        case .itemWent: grid.itemWent("a")
        }
    }

    /// Whether anything holds the scroll or stays lifted.
    static func isHeld(_ grid: PluckReplayGrid) -> Bool {
        grid.container.holdsItsScroll || grid.container.liftedItem != nil || grid.anyPinchHoldsItsItem
    }

    /// Replays `course`, then `endings` in order, then the quiet, then the
    /// next pinch on `next`, trying to scroll.
    static func replay(_ course: Course, _ endings: [Ending], next: Next, tuning: PluckTuning = PluckTuning()) -> Outcome {
        var grid = PluckReplayGrid(tuning: tuning)
        run(course, on: &grid)
        var time = 1.0
        for ending in endings {
            grid.advance(to: time)
            say(ending, on: &grid)
            time += 0.01
        }
        let heldAfterWords = isHeld(grid)
        time += quiet
        grid.advance(to: time)
        let heldOnceOver = isHeld(grid)
        let alarmed = !grid.alarms.isEmpty
        let netLetGo = grid.alarms.contains { $0.kind.letsGo }

        // The next pinch: it touches, and the scroll view takes it only if
        // its scroll is on as it touches.
        let heldAtNextTouch = grid.container.holdsItsScroll
        let item: String? = switch next {
        case .sameItem: "a"
        case .otherItem: "b"
        case .emptySpace: nil
        }
        if let item {
            grid.press(item, down: true)
        }
        time += 0.1
        grid.advance(to: time)
        if let item {
            grid.drag(item, 0, 15, 0)
        }
        if !heldAtNextTouch {
            grid.scrollPhase(.interacting)
            grid.scrollOffsetChanged(to: grid.scrollOffset + SIMD2(0, 40))
        }
        time += 0.2
        grid.advance(to: time)
        if let item {
            grid.dragStopped(item)
            grid.press(item, down: false)
        }
        grid.scrollPhase(.idle)
        time += quiet
        grid.advance(to: time)
        return Outcome(
            endings: endings,
            heldOnceOver: heldOnceOver,
            heldAtNextTouch: heldAtNextTouch,
            heldAfterNext: isHeld(grid),
            heldAfterWords: heldAfterWords,
            alarmed: alarmed,
            netLetGo: netLetGo,
            log: grid.log
        )
    }

    /// Every ordered choice of `endings`, each said or not: none, each one,
    /// each ordered pair, and so on to every order of all of them.
    static func orders(of endings: [Ending]) -> [[Ending]] {
        var result: [[Ending]] = [[]]
        func extend(_ prefix: [Ending], _ rest: [Ending]) {
            for (index, ending) in rest.enumerated() {
                var remaining = rest
                remaining.remove(at: index)
                let order = prefix + [ending]
                result.append(order)
                extend(order, remaining)
            }
        }
        extend([], endings)
        return result
    }

    /// The words that may end `course`: the drag's only if it spoke.
    static func endings(for course: Course) -> [Ending] {
        course.dragSpoke ? Ending.allCases : Ending.allCases.filter { $0 != .dragEnded && $0 != .dragCancelled }
    }

    /// Whether `endings` say `course`'s pinch was let go, as far as words
    /// can: the tap, or the item going, or, should the drag have spoken, its
    /// end or its cancel, or, with it silent, the press's end, after which
    /// nothing more can come. Without one, the words that say so went
    /// unheard.
    static func say(_ course: Course, isLetGo endings: [Ending]) -> Bool {
        if endings.contains(.tapped) || endings.contains(.itemWent) { return true }
        return course.dragSpoke
            ? endings.contains(.dragEnded) || endings.contains(.dragCancelled)
            : endings.contains(.pressEnded)
    }

    /// The failing replays, grouped by the words said, whatever their
    /// order, for a message: "PT: 2 of 2 orders held once over, ...".
    static func summary(_ outcomes: [Outcome]) -> String {
        var groups: [String: [Outcome]] = [:]
        for outcome in outcomes {
            groups[String(outcome.endings.map(\.rawValue).sorted()), default: []].append(outcome)
        }
        var lines: [String] = []
        for (said, group) in groups.sorted(by: { $0.key < $1.key }) {
            let failed = group.filter(\.failed)
            guard !failed.isEmpty else { continue }
            let over = failed.filter(\.heldOnceOver).count
            let touch = failed.filter(\.heldAtNextTouch).count
            let after = failed.filter(\.heldAfterNext).count
            lines.append("{\(said.isEmpty ? "none" : said)}: \(failed.count) of \(group.count) orders fail (held once over \(over), at the next touch \(touch), after the next \(after)); e.g. \(failed[0].spelled)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: The replays

    /// Where the words say the pinch was let go, the rules let the scroll go:
    /// nothing holds it once those words, and the quiet after them, have
    /// passed, wherever the next pinch lands.
    @Test(arguments: Course.allCases, Next.allCases)
    func theRulesLetTheScrollGoOnceTheirWordsSayThePinchIsOver(_ course: Course, _ next: Next) {
        let orders = Self.orders(of: Self.endings(for: course)).filter { Self.say(course, isLetGo: $0) }
        let outcomes = orders.map { Self.replay(course, $0, next: next) }
        let failed = outcomes.filter(\.failed)
        #expect(failed.isEmpty, "\(course.rawValue), next on \(next.rawValue): \(failed.count) of \(outcomes.count) orders fail:\n\(Self.summary(outcomes))")
    }

    /// Whatever words go unheard, nothing holds the scroll once the pinch is
    /// over, wherever the next pinch lands.
    @Test(arguments: Course.allCases, Next.allCases)
    func nothingHoldsTheScrollOnceThePinchIsOverWhateverWordsGoUnheard(_ course: Course, _ next: Next) {
        let outcomes = Self.orders(of: Self.endings(for: course)).map { Self.replay(course, $0, next: next) }
        let failed = outcomes.filter(\.failed)
        #expect(failed.isEmpty, "\(course.rawValue), next on \(next.rawValue): \(failed.count) of \(outcomes.count) orders fail:\n\(Self.summary(outcomes))")
    }

    /// The alarm is raised in exactly the replays where the safety net had
    /// to let the hold go: where the item stayed lifted past its pinch's
    /// words and those words don't say it was let go. Where they do, the
    /// rules let it go first, and no alarm comes.
    @Test(arguments: Course.allCases)
    func theAlarmIsRaisedExactlyWhereTheSafetyNetLetsGo(_ course: Course) {
        let outcomes = Self.orders(of: Self.endings(for: course)).map { Self.replay(course, $0, next: .emptySpace) }
        let wrong = outcomes.filter { $0.alarmed != ($0.heldAfterWords && !Self.say(course, isLetGo: $0.endings)) }
        #expect(wrong.isEmpty, "\(course.rawValue): the alarm is wrong for \(wrong.map(\.spelled).joined(separator: ", "))")
        #expect(outcomes.allSatisfy { !$0.alarmed || $0.netLetGo })
    }

    /// Where the rules can tell the pinch is over, they let the scroll go at
    /// once: right after the tap, the item going, or the drag's end or
    /// cancel, nothing holds it. Only a still lift whose press's end is the
    /// last word waits, for the quiet.
    @Test(arguments: Course.allCases)
    func aWordThatEndsThePinchLetsTheScrollGoAtOnce(_ course: Course) {
        let outcomes = Self.orders(of: Self.endings(for: course))
            .filter { order in [Ending.tapped, .itemWent, .dragEnded, .dragCancelled].contains { order.contains($0) } }
            .map { Self.replay(course, $0, next: .emptySpace) }
        let held = outcomes.filter(\.heldAfterWords)
        #expect(held.isEmpty, "\(course.rawValue): held right after \(held.map(\.spelled).joined(separator: ", "))")
    }

    /// The orders are every ordered choice: 1,957 of six words.
    @Test func theOrdersAreEveryOrderedChoice() {
        #expect(Self.orders(of: Ending.allCases).count == 1957)
        #expect(Self.orders(of: [.pressEnded, .tapped]).map { String($0.map(\.rawValue)) } == ["", "P", "PT", "T", "TP"])
    }
}
