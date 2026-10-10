import Testing
@testable import GestureCore

/// A pluckable container's watch over its hold: whether a pinch is under
/// way; the scroll held off until the pinch that took it lets go; the alarm
/// once an item stays lifted with no pinch under way for more than half a
/// second, once its views disagree, or once the scroll view never takes a
/// pinch told as a scroll; and the safety net, which lets a hold go once
/// nothing is heard from its pinch, or at once with no pinch on it.
@Suite struct PluckHoldWatchTests {
    let start = ContinuousClock.now

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    func pinch(press: Bool, drag: Bool = false, lifted: Bool = true) -> PluckHoldWatch<Int>.Pinch {
        .init(title: "item 7", pressIsDown: press, dragHasIt: drag, holdsItsItem: lifted)
    }

    /// A watch told of item 7's press at 0 and its lift at 0.25, as the
    /// container holds its scroll under it and the scroll view is given that.
    func lifted(press: Bool = true, drag: Bool = false) -> PluckHoldWatch<Int> {
        var watch = PluckHoldWatch<Int>()
        watch.pinch(7, is: pinch(press: true, lifted: false), at: at(0))
        watch.lifted(7, title: "item 7", at: at(0.25))
        watch.container(holds: true, lifted: 7, at: at(0.25))
        watch.pinch(7, is: pinch(press: press, drag: drag), at: at(0.25))
        watch.scrollGiven(heldOff: true, at: at(0.26))
        return watch
    }

    // MARK: The scroll hold

    /// The scroll is held off as the container holds it under a lifted item,
    /// and stays held once the item settles while the drag of the pinch that
    /// lifted it still has it, as through a carry, until that pinch lets go;
    /// its press alone keeps it held no longer than its item.
    @Test func theScrollStaysHeldUntilThePinchThatTookItLetsGo() {
        var watch = lifted(drag: true)
        #expect(watch.holdsTheScroll)
        #expect(watch.scrollHeldFor == 7)
        watch.settled(because: "broke free", at: at(0.5))
        watch.container(holds: false, lifted: nil, at: at(0.5))
        #expect(watch.holdsTheScroll)
        watch.pinch(7, is: pinch(press: false, drag: true, lifted: false), at: at(0.8))
        #expect(watch.holdsTheScroll)
        watch.pinch(7, is: nil, at: at(1.5))
        #expect(!watch.holdsTheScroll)
        #expect(watch.events.last?.what == "the scroll on again: its pinch is over")

        var pressed = lifted(press: true)
        pressed.settled(because: "the app settled it", at: at(0.5))
        pressed.container(holds: false, lifted: nil, at: at(0.5))
        #expect(!pressed.holdsTheScroll)
    }

    /// Tuned to, the scroll comes back as the item settles, mid-pinch, as it
    /// did from October 9 to 10.
    @Test func tunedToTheScrollComesBackMidPinch() {
        var watch = lifted(drag: true)
        watch.scrollComesBackMidPinch = true
        watch.settled(because: "broke free", at: at(0.5))
        watch.container(holds: false, lifted: nil, at: at(0.5))
        #expect(!watch.holdsTheScroll)
    }

    /// A pinch whose gestures have let go, its item settling: the scroll
    /// comes back with the item.
    @Test func theScrollComesBackWithAnItemNoGestureHas() {
        var watch = lifted()
        watch.pinch(7, is: pinch(press: false), at: at(0.3))
        watch.settled(because: "the quiet", at: at(0.8))
        watch.container(holds: false, lifted: nil, at: at(0.8))
        #expect(!watch.holdsTheScroll)
    }

    /// The scroll kept for a pinch whose item settled, nothing heard from it
    /// for three seconds, is let go by the net.
    @Test func theNetLetsGoAScrollKeptForAPinchUnheardFrom() {
        var watch = lifted(drag: true)
        watch.heard(nil, from: 7, title: "item 7", at: at(0.5))
        watch.settled(because: "broke free", at: at(0.5))
        watch.container(holds: false, lifted: nil, at: at(0.5))
        #expect(watch.nextCheck == at(0.5) + .seconds(3))
        #expect(watch.verdict(at: at(3.4)) == .fine)
        guard case .letGo(let alarm) = watch.verdict(at: at(0.5) + .seconds(3)) else {
            Issue.record("not let go")
            return
        }
        #expect(alarm.kind == .scrollLetGoWithNothingHeard)
        watch.raised(alarm, at: at(3.5))
        watch.releaseTheScroll(because: "the safety net", at: at(3.5))
        watch.scrollGiven(heldOff: false, at: at(3.5))
        #expect(!watch.holdsTheScroll)
        #expect(watch.nextCheck == nil)
    }

    // MARK: The lift's alarm and net

    /// A pinch held, its item lifted, heard from: no alarm, while its press
    /// is down and its drag speaks.
    @Test func aHeldPinchHeardFromRaisesNoAlarm() {
        var watch = lifted(drag: true)
        #expect(watch.isPinchUnderWay)
        for step in 1...50 {
            watch.heard(nil, from: 7, title: "item 7", at: at(0.25 + Double(step) / 10))
            #expect(watch.verdict(at: at(0.3 + Double(step) / 10)) == .fine)
        }
        #expect(watch.nextCheck == at(5.25) + .seconds(1))
    }

    /// A pinch that says it has the item, a gesture's claim, but from which
    /// nothing is heard for a second: the safety net lets the hold go, as
    /// for a gesture whose end went unheard, or a hand held still.
    @Test func aClaimNothingIsHeardFromIsLetGoAfterASecond() {
        var watch = lifted(press: false, drag: true)
        watch.heard(nil, from: 7, title: "item 7", at: at(0.6))
        let due = at(0.6) + .seconds(1)
        #expect(watch.nextCheck == due)
        #expect(watch.verdict(at: at(1.59)) == .fine)
        guard case .letGo(let alarm) = watch.verdict(at: due) else {
            Issue.record("not let go")
            return
        }
        #expect(alarm.kind == .letGoWithNothingHeard)
        #expect(alarm.kind.letsGo)
        #expect(alarm.unclaimedFor == .zero)
        #expect(alarm.line.hasPrefix("Scroll held by item 7 for 1.35 s with nothing heard from its pinch for 1.00 s, let go by the safety net"))
    }

    /// The net's time is the caller's to set, from its tuning.
    @Test func theNetsTimeIsTuned() {
        var watch = PluckHoldWatch<Int>()
        watch.unheardLimit = .seconds(2)
        watch.pinch(7, is: pinch(press: true, lifted: false), at: at(0))
        watch.lifted(7, title: "item 7", at: at(0.25))
        watch.container(holds: true, lifted: 7, at: at(0.25))
        #expect(watch.nextCheck == at(0.25) + .seconds(2))
        #expect(watch.verdict(at: at(2)) == .fine)
        guard case .letGo = watch.verdict(at: at(0.25) + .seconds(2)) else {
            Issue.record("not let go")
            return
        }
    }

    /// Its press gone as the item lifted, its drag silent: no pinch is under
    /// way, and the alarm comes once that has lasted more than half a
    /// second, once; the net lets it go a second after it was last heard
    /// from, its lift counting.
    @Test func aLiftKeptUpPastItsPressRaisesTheAlarmOnce() throws {
        var watch = lifted()
        watch.pinch(7, is: pinch(press: false), at: at(0.26))
        #expect(!watch.isPinchUnderWay)
        #expect(watch.unclaimedSince == at(0.26))
        #expect(watch.nextCheck == at(0.76))
        #expect(watch.verdict(at: at(0.5)) == .fine)
        #expect(watch.verdict(at: at(0.76)) == .fine)
        guard case .alarm(let alarm) = watch.verdict(at: at(0.8)) else {
            Issue.record("no alarm")
            return
        }
        #expect(alarm.kind == .heldWithNoPinchUnderWay)
        #expect(!alarm.kind.letsGo)
        #expect(alarm.heldFor == at(0.8) - at(0.25))
        #expect(alarm.unclaimedFor == at(0.8) - at(0.26))
        #expect(alarm.line == "Scroll held by item 7 for 0.55 s with no pinch under way for 0.54 s; its pinch: item 7: press up, drag silent or ended, its item kept up past its press")
        watch.raised(alarm, at: at(0.8))
        #expect(watch.alarms == 1)
        #expect(watch.lastAlarm == alarm.line)
        #expect(watch.verdict(at: at(1)) == .fine)
        #expect(watch.nextCheck == at(0.25) + .seconds(1))
        guard case .letGo(let net) = watch.verdict(at: at(0.25) + .seconds(1)) else {
            Issue.record("not let go")
            return
        }
        #expect(net.kind == .letGoWithNothingHeard)
        watch.raised(net, at: at(1.25))
        watch.releaseTheScroll(because: "the safety net", at: at(1.25))
        watch.settled(because: "the safety net", at: at(1.25))
        watch.container(holds: false, lifted: nil, at: at(1.25))
        #expect(watch.alarms == 2)
        #expect(!watch.holdsTheScroll)
    }

    /// A pinch's drag having it backs the hold, as its press does; its end
    /// and its settle end the hold and the watch's count.
    @Test func aDragOrASettleEndsTheCount() {
        var watch = lifted()
        watch.pinch(7, is: pinch(press: false), at: at(0.26))
        watch.pinch(7, is: pinch(press: false, drag: true), at: at(0.5))
        watch.heard("drag spoke", from: 7, title: "item 7", at: at(0.5))
        #expect(watch.unclaimedSince == nil)
        #expect(watch.verdict(at: at(1.4)) == .fine)
        watch.pinch(7, is: pinch(press: false, drag: false), at: at(1.45))
        watch.settled(because: "the drag ended", at: at(1.45))
        watch.container(holds: false, lifted: nil, at: at(1.45))
        watch.scrollGiven(heldOff: false, at: at(1.46))
        #expect(watch.heldItem == nil)
        #expect(!watch.holdsTheScroll)
        #expect(watch.unclaimedSince == nil)
        #expect(watch.verdict(at: at(4)) == .fine)
        #expect(watch.nextCheck == nil)
    }

    /// A pinch over while its item stays lifted: the safety net lets the
    /// hold go at once, there being no pinch on it.
    @Test func aPinchOverWithItsItemUpIsLetGoAtOnce() {
        var watch = lifted()
        watch.pinch(7, is: nil, at: at(0.4))
        guard case .letGo(let alarm) = watch.verdict(at: at(0.4)) else {
            Issue.record("not let go")
            return
        }
        #expect(alarm.kind == .letGoWithNoPinchOnIt)
        #expect(alarm.pinch == nil)
        #expect(alarm.line == "Scroll held by item 7 for 0.15 s with no pinch on it, let go by the safety net")
    }

    /// A pinch on another item, its press down, is a pinch under way.
    @Test func aPinchElsewhereIsAPinchUnderWay() {
        var watch = lifted()
        watch.pinch(7, is: pinch(press: false), at: at(0.26))
        watch.pinch(8, is: .init(title: "item 8", pressIsDown: true, dragHasIt: false, holdsItsItem: false), at: at(0.5))
        #expect(watch.isPinchUnderWay)
        #expect(watch.verdict(at: at(1.2)) == .fine)
    }

    // MARK: Its views

    /// The value the scroll view was given, the container's hold, and what a
    /// probe reads the scroll view as having, against the watch's own: a
    /// disagreement a quarter second long raises the alarm, once, until they
    /// agree again.
    @Test func viewsThatDisagreeRaiseTheAlarm() {
        var watch = PluckHoldWatch<Int>()
        let on = PluckHoldWatch<Int>.ScrollViewReading(scrollEnabled: true, panEnabled: true, panState: "possible", tracking: false, dragging: false, decelerating: false)
        watch.scrollGiven(heldOff: false, at: at(0))
        watch.scrollViewRead(on, at: at(0))
        #expect(watch.disagreement == nil)
        #expect(watch.nextCheck == nil)

        // Given held off with the watch holding nothing.
        watch.scrollGiven(heldOff: true, at: at(1))
        #expect(watch.disagreement == "the scroll view was given held off, the watch has it on; the scroll view was given held off, and has scrolling on, pan on, pan possible")
        #expect(watch.nextCheck == at(1) + .milliseconds(250))
        #expect(watch.verdict(at: at(1.2)) == .fine)
        guard case .alarm(let alarm) = watch.verdict(at: at(1) + .milliseconds(250)) else {
            Issue.record("no alarm")
            return
        }
        #expect(alarm.kind == .viewsDisagree)
        watch.raised(alarm, at: at(1.25))
        #expect(watch.verdict(at: at(2)) == .fine)
        watch.scrollGiven(heldOff: false, at: at(2))
        #expect(watch.disagreement == nil)

        // The scroll view's pan off with the scroll given on.
        let panOff = PluckHoldWatch<Int>.ScrollViewReading(scrollEnabled: true, panEnabled: false, panState: "possible", tracking: false, dragging: false, decelerating: false)
        watch.scrollViewRead(panOff, at: at(3))
        #expect(watch.disagreement == "the scroll view was given on, and has scrolling on, pan off, pan possible")

        // The container's lifted item against the watch's.
        var lifted = PluckHoldWatch<Int>()
        lifted.container(holds: true, lifted: 7, at: at(0))
        #expect(lifted.disagreement == "the container has an item lifted, the watch none")
        #expect(lifted.holdsTheScroll)
        lifted.lifted(7, title: "item 7", at: at(0.01))
        #expect(lifted.disagreement == nil)
        #expect(lifted.scrollHeldTitle == "item 7")
    }

    /// A pinch told as a scroll, which the scroll view doesn't take in 0.3 s,
    /// no phase of scrolling nor its pan begun: the alarm says it never took
    /// it. One the scroll view takes, by a phase or its pan, raises nothing.
    @Test func aScrollTheScrollViewNeverTookRaisesTheAlarm() {
        var watch = PluckHoldWatch<Int>()
        watch.scrollGiven(heldOff: false, at: at(0))
        watch.ruledAScroll(on: "item 99", at: at(1))
        #expect(watch.nextCheck == at(1) + .milliseconds(300))
        #expect(watch.verdict(at: at(1.2)) == .fine)
        guard case .alarm(let alarm) = watch.verdict(at: at(1) + .milliseconds(300)) else {
            Issue.record("no alarm")
            return
        }
        #expect(alarm.kind == .scrollViewNeverTookIt)
        #expect(alarm.line.hasPrefix("The scroll view never took the scroll of the pinch on item 99: no phase of scrolling, nor its pan begun, 0.30 s after the rules told it as one; scroll on; given on"))
        watch.raised(alarm, at: at(1.3))
        #expect(watch.nextCheck == nil)

        var taken = PluckHoldWatch<Int>()
        taken.ruledAScroll(on: "item 48", at: at(1))
        taken.scrollViewSaid(.interacting, at: at(1.1))
        #expect(taken.verdict(at: at(1.5)) == .fine)
        // One told while it scrolls already raises nothing.
        taken.ruledAScroll(on: "item 49", at: at(1.2))
        #expect(taken.scrollRulingAt == nil)

        var panned = PluckHoldWatch<Int>()
        panned.ruledAScroll(on: "item 50", at: at(1))
        let began = PluckHoldWatch<Int>.ScrollViewReading(scrollEnabled: true, panEnabled: true, panState: "began", tracking: true, dragging: true, decelerating: false)
        panned.scrollViewRead(began, panBegan: true, at: at(1.05))
        #expect(panned.verdict(at: at(1.5)) == .fine)
    }

    // MARK: Its words

    /// It keeps the last ten things told, oldest first; a drag's every move
    /// notes only when the held item's pinch was last heard; an alarm's lines
    /// are the state and those ten, each with how long before it came.
    @Test func itKeepsTheLastTenThingsToldForAnAlarm() {
        var watch = lifted()
        watch.heard("press down", from: 7, title: "item 7", at: at(0.25))
        for step in 1...12 {
            watch.heard("drag \(step)", from: 7, title: "item 7", at: at(0.25 + Double(step) / 100))
        }
        watch.heard(nil, from: 7, title: "item 7", at: at(0.5))
        watch.heard(nil, from: 8, title: "item 8", at: at(0.6))
        #expect(watch.lastHeard == at(0.5))
        #expect(watch.events.count == 10)
        #expect(watch.events.first?.what == "item 7: drag 3")
        #expect(watch.events.last?.what == "item 7: drag 12")
        let alarm = PluckHoldWatch<Int>.Alarm(kind: .heldWithNoPinchUnderWay, title: "item 7", heldFor: .seconds(1), unclaimedFor: .seconds(1), unheardFor: .seconds(1), pinch: nil)
        let lines = watch.alarmLines(for: alarm, at: at(1.25))
        #expect(lines.count == 11)
        #expect(lines[0].name == "state")
        #expect(lines[0].detail == "scroll held off for item 7 for 1.00 s; given held off; container holds, an item lifted; item 7 lifted for 1.00 s; its pinch last heard 0.75 s ago; no phase yet; pinch on item 7: press down, drag silent or ended, its item lifted")
        #expect(lines[1].name == "event 1")
        #expect(lines[1].detail == "-0.97 s: item 7: drag 3")
    }

    /// The state line says each view of the hold, the scroll view's last
    /// phase, and the pinch under way.
    @Test func theStateLineSaysEachView() {
        var watch = PluckHoldWatch<Int>()
        #expect(watch.stateLine(at: at(0)) == "scroll on; given nothing yet; container doesn't hold, nothing lifted; nothing lifted; no phase yet; no pinch")
        watch.pinch(3, is: .init(title: "item 3", pressIsDown: true, dragHasIt: true, holdsItsItem: false), at: at(0))
        watch.scrollViewSaid(.tracking, at: at(0.1))
        watch.scrollViewRead(.init(scrollEnabled: true, panEnabled: true, panState: "possible", tracking: true, dragging: false, decelerating: false), at: at(0.1))
        #expect(watch.stateLine(at: at(0.5)) == "scroll on; given nothing yet; container doesn't hold, nothing lifted; nothing lifted; scroll view scrolling on, pan on, pan possible, tracking; last phase tracking 0.40 s ago; pinch on item 3: press down, drag has it, its item down")
    }
}
