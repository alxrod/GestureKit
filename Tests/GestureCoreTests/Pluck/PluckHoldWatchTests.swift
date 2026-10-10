import Testing
@testable import GestureCore

/// A pluckable container's watch over its hold: whether a pinch is under
/// way, what a status line says, the alarm once an item stays lifted with no
/// pinch under way for more than half a second, and the safety net, which
/// lets a hold go once nothing is heard from its pinch for a second, or at
/// once with no pinch on it.
@Suite struct PluckHoldWatchTests {
    let start = ContinuousClock.now

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    func pinch(press: Bool, drag: Bool = false, lifted: Bool = true) -> PluckHoldWatch<Int>.Pinch {
        .init(title: "item 7", pressIsDown: press, dragHasIt: drag, holdsItsItem: lifted)
    }

    /// A pinch held, its item lifted, heard from: no alarm, while its press
    /// is down and its drag speaks.
    @Test func aHeldPinchHeardFromRaisesNoAlarm() {
        var watch = PluckHoldWatch<Int>()
        watch.pinch(7, is: pinch(press: true, lifted: false), at: at(0))
        watch.lifted(7, title: "item 7", at: at(0.25))
        watch.pinch(7, is: pinch(press: true, drag: true), at: at(0.25))
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
        var watch = PluckHoldWatch<Int>()
        watch.pinch(7, is: pinch(press: false, drag: true, lifted: false), at: at(0.1))
        watch.lifted(7, title: "item 7", at: at(0.25))
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
        var watch = PluckHoldWatch<Int>()
        watch.pinch(7, is: pinch(press: true, lifted: false), at: at(0))
        watch.lifted(7, title: "item 7", at: at(0.25))
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
        watch.settled(because: "the safety net", at: at(1.25))
        #expect(watch.alarms == 1)
        #expect(watch.nextCheck == nil)
    }

    /// A pinch's drag having it backs the hold, as its press does; its end
    /// or its settle ends the watch's count.
    @Test func aDragOrASettleEndsTheCount() {
        var watch = PluckHoldWatch<Int>()
        watch.pinch(7, is: pinch(press: true, lifted: false), at: at(0))
        watch.lifted(7, title: "item 7", at: at(0.25))
        watch.pinch(7, is: pinch(press: false), at: at(0.26))
        watch.pinch(7, is: pinch(press: false, drag: true), at: at(0.5))
        watch.heard("drag spoke", from: 7, title: "item 7", at: at(0.5))
        #expect(watch.unclaimedSince == nil)
        #expect(watch.verdict(at: at(1.4)) == .fine)
        watch.pinch(7, is: pinch(press: false, drag: false), at: at(1.45))
        watch.settled(because: "the drag ended", at: at(1.45))
        #expect(watch.heldItem == nil)
        #expect(watch.unclaimedSince == nil)
        #expect(watch.verdict(at: at(4)) == .fine)
        #expect(watch.nextCheck == nil)
    }

    /// A pinch over while its item stays lifted: the safety net lets the
    /// hold go at once, there being no pinch on it.
    @Test func aPinchOverWithItsItemUpIsLetGoAtOnce() {
        var watch = PluckHoldWatch<Int>()
        watch.pinch(7, is: pinch(press: true), at: at(0))
        watch.lifted(7, title: "item 7", at: at(0.25))
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
        var watch = PluckHoldWatch<Int>()
        watch.pinch(7, is: pinch(press: true, lifted: false), at: at(0))
        watch.lifted(7, title: "item 7", at: at(0.25))
        watch.pinch(7, is: pinch(press: false), at: at(0.26))
        watch.pinch(8, is: .init(title: "item 8", pressIsDown: true, dragHasIt: false, holdsItsItem: false), at: at(0.5))
        #expect(watch.isPinchUnderWay)
        #expect(watch.verdict(at: at(1.2)) == .fine)
    }

    /// It keeps the last ten things told, oldest first; a drag's every move
    /// notes only when the held item's pinch was last heard; an alarm's lines
    /// are the state and those ten, each with how long before it came.
    @Test func itKeepsTheLastTenThingsToldForAnAlarm() {
        var watch = PluckHoldWatch<Int>()
        watch.pinch(7, is: pinch(press: true, lifted: false), at: at(0))
        watch.heard("press down", from: 7, title: "item 7", at: at(0))
        watch.lifted(7, title: "item 7", at: at(0.25))
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
        #expect(lines[0].detail == "scroll held by item 7 for 1.00 s; its pinch last heard 0.75 s ago; pinch on item 7: press down, drag silent or ended, its item down")
        #expect(lines[1].name == "event 1")
        #expect(lines[1].detail == "-0.97 s: item 7: drag 3")
    }

    /// The state line says the scroll is on, and what pinch is under way.
    @Test func theStateLineSaysWhatsHeldAndWhatPinches() {
        var watch = PluckHoldWatch<Int>()
        #expect(watch.stateLine(at: at(0)) == "scroll on; no pinch")
        watch.pinch(3, is: .init(title: "item 3", pressIsDown: true, dragHasIt: true, holdsItsItem: false), at: at(0))
        #expect(watch.stateLine(at: at(0)) == "scroll on; pinch on item 3: press down, drag has it, its item down")
    }
}
