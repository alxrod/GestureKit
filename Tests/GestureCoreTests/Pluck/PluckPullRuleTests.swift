import Foundation
import Testing
@testable import GestureCore

/// When a move of a lifted item's armed pinch pulls it out, by each rule.
@Suite struct PluckPullRuleTests {
    let threshold = 27.0

    // MARK: Out of the plane, the default: 2 cm toward the viewer, drifting
    // across the container at most twice as far as it comes.

    func isPull(_ x: Double, _ y: Double, _ z: Double) -> Bool {
        PluckTuning().pullRule.isPull(SIMD3(x, y, z), threshold: threshold)
    }

    @Test func theDefaultPullTakesOneDeepForEveryTwoAcross() {
        #expect(PluckTuning().pullRule == .outOfThePlane(depthPerDrift: 0.5))
    }

    @Test func aStraightPullPastTheThresholdPulls() {
        #expect(isPull(0, 0, 27))
        #expect(isPull(0, 0, 60))
    }

    @Test func aPullShortOfTheThresholdDoesNot() {
        #expect(!isPull(0, 0, 26.9))
    }

    @Test func aPullAwayFromTheViewerDoesNot() {
        #expect(!isPull(0, 0, -40))
    }

    /// A sweep across the container or up it, as a scroll, picks up some
    /// depth as the hand arcs, but stays a small part of the sweep, so it
    /// pulls nothing however deep it goes.
    @Test func aMostlySidewaysDragIsNotAPull() {
        #expect(!isPull(0, 200, 40))
        #expect(!isPull(120, 0, 5))
        #expect(!isPull(0, -260, 30))
    }

    /// A pull that drifts across the container, as hands do coming in, is
    /// still a pull.
    @Test func aPullWithSomeDriftPulls() {
        #expect(isPull(10, 15, 30))
        #expect(isPull(40, 0, 27))
        #expect(isPull(0, 54, 27))
    }

    /// Depth must be at least half the drift across the container, measured
    /// in its plane as one distance.
    @Test func theRatioBoundary() {
        #expect(isPull(54, 0, 27))
        #expect(!isPull(54.1, 0, 27))
        #expect(isPull(36, 48, 30))
        #expect(!isPull(36, 48, 29.9))
    }

    @Test func aNonFiniteTranslationIsNotAPull() {
        #expect(!isPull(.nan, 0, 40))
        #expect(!isPull(0, 0, .infinity))
        #expect(PluckTuning().pullRule.judge(SIMD3(.nan, 0, 40), threshold: threshold).verdict == .notANumber)
    }

    /// Its judgement says how deep and how far across a move went, against
    /// what it needed, and why it didn't pull.
    @Test func itsJudgementSaysWhy() {
        let rule = PluckPullRule.outOfThePlane(depthPerDrift: 0.5)
        #expect(rule.judge(SIMD3(36, 48, 30), threshold: threshold) == PluckPullJudgement(depth: 30, drift: 60, threshold: 27, verdict: .pulls))
        #expect(rule.judge(SIMD3(0, 0, 20), threshold: threshold).verdict == .tooShallow)
        #expect(rule.judge(SIMD3(0, 200, 40), threshold: threshold).verdict == .tooSlanted)
    }

    /// A steeper rule turns down a slant the default takes.
    @Test func aSteeperRuleTurnsDownASlant() {
        let steep = PluckPullRule.outOfThePlane(depthPerDrift: 1)
        #expect(!steep.isPull(SIMD3(40, 0, 30), threshold: threshold))
        #expect(steep.isPull(SIMD3(30, 0, 30), threshold: threshold))
    }

    // MARK: Toward the viewer, however far across.

    @Test func towardTheViewerTakesAnyDrift() {
        let rule = PluckPullRule.towardTheViewer
        #expect(rule.isPull(SIMD3(0, 200, 40), threshold: threshold))
        #expect(rule.isPull(SIMD3(0, 0, 27), threshold: threshold))
        #expect(rule.judge(SIMD3(500, 0, 26.9), threshold: threshold).verdict == .tooShallow)
        #expect(!rule.isPull(SIMD3(0, 0, -40), threshold: threshold))
    }

    // MARK: Any direction.

    /// Any move as far as the pull's distance pulls, across, away, or
    /// toward the viewer.
    @Test func anyDirectionTakesAnyMoveFarEnough() {
        let rule = PluckPullRule.anyDirection
        #expect(rule.isPull(SIMD3(27, 0, 0), threshold: threshold))
        #expect(rule.isPull(SIMD3(0, 0, -27), threshold: threshold))
        #expect(rule.isPull(SIMD3(0, 20, -20), threshold: threshold))
        #expect(rule.judge(SIMD3(10, 10, 10), threshold: threshold).verdict == .tooShort)
    }

    /// A rule is a value a trace can keep and the lab can send.
    @Test func aRuleRoundTripsThroughJSON() throws {
        for rule in [PluckPullRule.outOfThePlane(depthPerDrift: 0.75), .towardTheViewer, .anyDirection] {
            let data = try JSONEncoder().encode(rule)
            #expect(try JSONDecoder().decode(PluckPullRule.self, from: data) == rule)
        }
    }
}
