import GestureCore
import Testing

@Suite("Trace pacing")
struct TracePacingTests {
    let start = ContinuousClock.now

    func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    @Test("The first change shows at once")
    func firstChange() {
        var pacing = TracePacing()
        #expect(pacing.changed(at: at(0)) == .now)
    }

    @Test("A change within the interval of a showing shows as the interval ends, with any after it")
    func burst() {
        var pacing = TracePacing()
        #expect(pacing.changed(at: at(0)) == .now)
        pacing.shown(at: at(0))
        #expect(pacing.changed(at: at(30)) == .at(at(100)))
        #expect(pacing.changed(at: at(60)) == .alreadyDue)
        #expect(pacing.changed(at: at(99)) == .alreadyDue)
        pacing.shown(at: at(100))
        #expect(pacing.changed(at: at(150)) == .at(at(200)))
    }

    @Test("A change after a quiet spell shows at once again")
    func quietSpell() {
        var pacing = TracePacing()
        #expect(pacing.changed(at: at(0)) == .now)
        pacing.shown(at: at(0))
        #expect(pacing.changed(at: at(100)) == .now)
        pacing.shown(at: at(100))
        #expect(pacing.changed(at: at(500)) == .now)
    }

    @Test("A showing done early, as a cleared trace's, ends the one due")
    func shownEarly() {
        var pacing = TracePacing()
        pacing.shown(at: at(0))
        #expect(pacing.changed(at: at(20)) == .at(at(100)))
        pacing.shown(at: at(40))
        #expect(pacing.changed(at: at(60)) == .at(at(140)))
    }

    @Test("Its interval can be told")
    func interval() {
        var pacing = TracePacing(interval: .milliseconds(250))
        pacing.shown(at: at(0))
        #expect(pacing.interval == .milliseconds(250))
        #expect(pacing.changed(at: at(100)) == .at(at(250)))
    }
}
