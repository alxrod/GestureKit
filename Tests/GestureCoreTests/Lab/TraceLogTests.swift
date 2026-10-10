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

    @Test("A log keeps at least one interaction, of at least one line")
    func leastCapacity() {
        #expect(TraceLog(capacity: 0).capacity == 1)
        #expect(TraceLog().capacity == TraceLog.defaultCapacity)
        #expect(TraceLog(lineLimit: 0).lineLimit == 1)
        #expect(TraceLog().lineLimit == TraceLog.defaultLineLimit)
        #expect(TraceLog().foldSpan == .seconds(1))
    }

    @Test("A run of one name folds into one line: how many, the first and the latest, and the farthest")
    func foldsARun() throws {
        var log = TraceLog()
        let id = log.begin("Carry", title: "Pinch on a handle", at: at(0), date: date)
        log.record("touch", in: id, at: at(0))
        log.record("carry", detail: "hand 0.10 m", measure: TraceMeasure(0.10, "m"), in: id, at: at(200))
        log.record("carry", detail: "hand 0.30 m", measure: TraceMeasure(0.30, "m"), in: id, at: at(500))
        log.record("carry", detail: "hand 0.20 m", measure: TraceMeasure(0.20, "m"), in: id, at: at(900))
        log.record("release", detail: "let go", in: id, at: at(1_000))
        let events = log.interactions[0].events
        #expect(events.map(\.name) == ["touch", "carry", "release"])
        let run = events[1]
        #expect(run.count == 3)
        #expect(run.isFolded)
        #expect(run.offset == .milliseconds(200))
        #expect(run.latestOffset == .milliseconds(900))
        #expect(run.detail == "hand 0.10 m")
        #expect(run.latestDetail == "hand 0.20 m")
        #expect(run.farthest == TraceMeasure(0.30, "m"))
        #expect(run.text == "carry ×3 +0.20–0.90 s (farthest 0.30 m; hand 0.10 m … hand 0.20 m)")
        #expect(log.interactions[0].eventsRecorded == 5)
        log.finish(id, outcome: "carried", at: at(1_000))
        #expect(log.interactions[0].summary == """
            #1 Carry · Pinch on a handle → carried, 1.00 s: touch +0.00 s; \
            carry ×3 +0.20–0.90 s (farthest 0.30 m; hand 0.10 m … hand 0.20 m); release +1.00 s (let go)
            """)
    }

    @Test("A change of name always begins a line, and a name after a pause begins another")
    func stagesAndPauses() {
        var log = TraceLog()
        let id = log.begin("Pluck", title: "Pinch on item 4", at: at(0), date: date)
        log.record("drag", detail: "a", in: id, at: at(0))
        log.record("drag", detail: "b", in: id, at: at(100))
        log.record("lift", in: id, at: at(150))
        log.record("drag", detail: "c", in: id, at: at(200))
        log.record("drag", detail: "d", in: id, at: at(1_200))
        log.record("drag", detail: "e", in: id, at: at(2_300))
        let events = log.interactions[0].events
        #expect(events.map(\.name) == ["drag", "lift", "drag", "drag"])
        #expect(events.map(\.count) == [2, 1, 2, 1])
        #expect(events[2].latestDetail == "d")
        #expect(events[3].detail == "e")
        #expect(events[3].offset == .milliseconds(2_300))
    }

    @Test("A full interaction folds a name it has had into that name's latest line, and keeps a new one")
    func lineLimit() {
        var log = TraceLog(lineLimit: 3)
        let id = log.begin("Pluck", title: "Pinch", at: at(0), date: date)
        log.record("drag", detail: "1", in: id, at: at(0))
        log.record("scroll phase", detail: "interacting", in: id, at: at(10))
        log.record("drag", detail: "2", in: id, at: at(20))
        // Full: these fold into the latest line of their names.
        log.record("scroll phase", detail: "idle", in: id, at: at(30))
        log.record("drag", detail: "3", in: id, at: at(40))
        log.record("drag", detail: "4", in: id, at: at(5_000))
        // A name it hasn't had is a stage, kept past the limit.
        log.record("lift", in: id, at: at(5_100))
        let events = log.interactions[0].events
        #expect(events.map(\.name) == ["drag", "scroll phase", "drag", "lift"])
        #expect(events.map(\.count) == [1, 2, 3, 1])
        #expect(events[1].latestDetail == "idle")
        #expect(events[2].latestDetail == "4")
        #expect(events[2].latestOffset == .milliseconds(5_000))
    }

    @Test("A run's farthest is in its unit; a measure in another unit takes its place")
    func farthestUnits() {
        var log = TraceLog()
        let id = log.begin("A", title: "a", at: at(0), date: date)
        log.record("move", measure: TraceMeasure(12, "pt", decimals: 1), in: id, at: at(0))
        log.record("move", measure: TraceMeasure(3, "pt", decimals: 1), in: id, at: at(10))
        #expect(log.interactions[0].events[0].farthest?.text == "12.0 pt")
        log.record("move", measure: TraceMeasure(0.02, "m"), in: id, at: at(20))
        log.record("move", in: id, at: at(30))
        let run = log.interactions[0].events[0]
        #expect(run.farthest == TraceMeasure(0.02, "m"))
        #expect(run.count == 4)
        #expect(run.text == "move ×4 +0.00–0.03 s (farthest 0.02 m)")
    }
}
