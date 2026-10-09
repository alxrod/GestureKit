import Foundation
import GestureCore
import Testing

@Suite("Trace log")
struct TraceLogTests {
    let start = ContinuousClock.now
    let date = Date(timeIntervalSinceReferenceDate: 0)

    func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    @Test("An interaction keeps its events, timed from its beginning, and its outcome")
    func interaction() throws {
        var log = TraceLog()
        let id = log.begin("Trace check", title: "Pinch on the cube", at: at(1_000), date: date)
        log.record("touch", detail: "size 0.20 m", in: id, at: at(1_000))
        log.record("release", detail: "moved 0.2 cm", in: id, at: at(1_120))
        let outcome = log.finish(id, outcome: "tap", at: at(1_130))
        let finished = try #require(outcome)

        #expect(finished.id == 1)
        #expect(finished.gesture == "Trace check")
        #expect(finished.title == "Pinch on the cube")
        #expect(finished.date == date)
        #expect(finished.events == [
            TraceEvent(offset: .zero, name: "touch", detail: "size 0.20 m"),
            TraceEvent(offset: .milliseconds(120), name: "release", detail: "moved 0.2 cm"),
        ])
        #expect(finished.outcome == "tap")
        #expect(finished.lasted == .milliseconds(130))
        #expect(!finished.isUnderWay)
        #expect(log.interaction(withID: id) == finished)
        #expect(finished.summary
            == "#1 Trace check · Pinch on the cube → tap, 0.13 s: touch +0.00 s (size 0.20 m); release +0.12 s (moved 0.2 cm)")
    }

    @Test("An interaction under way says so")
    func underWay() {
        var log = TraceLog()
        let id = log.begin("Pluck", title: "Pinch on item 4", at: at(0), date: date)
        #expect(log.interactions[0].summary == "#1 Pluck · Pinch on item 4 → under way")
        log.record("lift", in: id, at: at(500))
        #expect(log.interactions[0].isUnderWay)
        #expect(log.interactions[0].summary == "#1 Pluck · Pinch on item 4 → under way: lift +0.50 s")
    }

    @Test("Interactions are kept newest first, the oldest going past the capacity")
    func capacity() {
        var log = TraceLog(capacity: 2)
        let first = log.begin("A", title: "first", at: at(0), date: date)
        let second = log.begin("A", title: "second", at: at(10), date: date)
        let third = log.begin("A", title: "third", at: at(20), date: date)
        #expect([first, second, third] == [1, 2, 3] as [TracedInteraction.ID])
        #expect(log.interactions.map(\.title) == ["third", "second"])
        log.record("late", in: first, at: at(30))
        #expect(log.finish(first, outcome: "tap", at: at(30)) == nil)
        #expect(log.interaction(withID: first) == nil)
    }

    @Test("Clearing forgets every interaction, and the numbers go on")
    func clearing() {
        var log = TraceLog()
        log.begin("A", title: "one", at: at(0), date: date)
        log.clear()
        #expect(log.interactions.isEmpty)
        #expect(log.begin("A", title: "two", at: at(10), date: date) == 2)
    }

    @Test("An outcome is given once; events may follow it")
    func afterTheOutcome() {
        var log = TraceLog()
        let id = log.begin("Coast", title: "Flick", at: at(0), date: date)
        log.finish(id, outcome: "coast", at: at(200))
        #expect(log.finish(id, outcome: "tap", at: at(300)) == nil)
        log.record("stopped", detail: "after 1.2 m", in: id, at: at(1_400))
        let interaction = log.interactions[0]
        #expect(interaction.outcome == "coast")
        #expect(interaction.lasted == .milliseconds(200))
        #expect(interaction.events.map(\.name) == ["stopped"])
        #expect(interaction.events[0].offset == .milliseconds(1_400))
    }

    @Test("A time before an interaction began counts as its beginning")
    func earlyTimes() {
        var log = TraceLog()
        let id = log.begin("A", title: "early", at: at(100), date: date)
        log.record("touch", in: id, at: at(40))
        log.finish(id, outcome: "nothing", at: at(50))
        #expect(log.interactions[0].events[0].offset == .zero)
        #expect(log.interactions[0].lasted == .zero)
    }

    @Test("A log keeps at least one interaction")
    func leastCapacity() {
        #expect(TraceLog(capacity: 0).capacity == 1)
        #expect(TraceLog().capacity == TraceLog.defaultCapacity)
    }
}
