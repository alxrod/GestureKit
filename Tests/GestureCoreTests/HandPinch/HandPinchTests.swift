import Testing
@testable import GestureCore

/// A hand's pinch from hand tracking's thumb and index fingertips: closing
/// below 2 cm, opening past 3.5 cm, let go once untracked three tenths of a
/// second; and the hand a press came from, the one pinched whose pinch
/// closed nearest it.
@Suite struct HandPinchTests {
    let start = ContinuousClock.now
    let tuning = HandPinchTuning()

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    /// The fingertips `gap` apart along x, about `middle`.
    func tips(_ gap: Float, about middle: SIMD3<Float> = SIMD3(0, 1, -0.5)) -> (SIMD3<Float>, SIMD3<Float>) {
        (middle - SIMD3(gap / 2, 0, 0), middle + SIMD3(gap / 2, 0, 0))
    }

    @Test func itClosesAndOpensWithAGapBetween() {
        var pinch = HandPinch()
        var (thumb, index) = tips(0.05)
        #expect(pinch.saw(thumbTip: thumb, indexTip: index, at: at(0), tuning: tuning) == nil)
        (thumb, index) = tips(0.019)
        #expect(pinch.saw(thumbTip: thumb, indexTip: index, at: at(0.1), tuning: tuning) == .closed)
        #expect(pinch.isPinched)
        #expect(pinch.closedAt == at(0.1))
        #expect(pinch.position == SIMD3(0, 1, -0.5))
        // Jitter between the gaps changes nothing.
        (thumb, index) = tips(0.03)
        #expect(pinch.saw(thumbTip: thumb, indexTip: index, at: at(0.2), tuning: tuning) == nil)
        #expect(pinch.isPinched)
        (thumb, index) = tips(0.036, about: SIMD3(0.1, 1, -0.5))
        #expect(pinch.saw(thumbTip: thumb, indexTip: index, at: at(0.3), tuning: tuning) == .opened)
        #expect(!pinch.isPinched)
        #expect(pinch.closedAt == nil)
        #expect(pinch.position == SIMD3(0.1, 1, -0.5))
    }

    @Test func aPinchedHandUntrackedIsLetGo() {
        var pinch = HandPinch()
        let (thumb, index) = tips(0.01)
        pinch.saw(thumbTip: thumb, indexTip: index, at: at(0), tuning: tuning)
        #expect(pinch.unseen(at: at(0.3), tuning: tuning) == nil)
        #expect(pinch.unseen(at: at(0.31), tuning: tuning) == .lost)
        #expect(!pinch.isPinched)
        var open = HandPinch()
        #expect(open.unseen(at: at(5), tuning: tuning) == nil)
    }

    /// The press came from the hand pinched now whose pinch closed nearest
    /// it, before or after; none with neither pinched.
    @Test func thePressCameFromTheHandPinchedNearestIt() {
        var left = HandPinch()
        var right = HandPinch()
        let (thumb, index) = tips(0.01)
        left.saw(thumbTip: thumb, indexTip: index, at: at(0), tuning: tuning)
        right.saw(thumbTip: thumb, indexTip: index, at: at(1.1), tuning: tuning)
        #expect(HandPinch.hand(pinchedNearest: at(1), among: [.left: left, .right: right]) == .right)
        #expect(HandPinch.hand(pinchedNearest: at(0.2), among: [.left: left, .right: right]) == .left)
        let (apart, apartIndex) = tips(0.05)
        right.saw(thumbTip: apart, indexTip: apartIndex, at: at(1.2), tuning: tuning)
        #expect(HandPinch.hand(pinchedNearest: at(1), among: [.left: left, .right: right]) == .left)
        #expect(HandPinch.hand(pinchedNearest: at(1), among: [:]) == nil)
    }

    @Test func itsTuningIsSound() {
        #expect(HandPinchTuning.parameterProblems.isEmpty)
        #expect(HandPinchTuning.defaults == HandPinchTuning(closesBelow: 0.02, opensAbove: 0.035, lostAfter: 0.3))
    }
}
