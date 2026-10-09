import Testing
@testable import GestureCore

/// The placement's tuning as the lab tunes it.
@Suite struct PlacementTuningTests {
    @Test func itsParametersAreSound() {
        #expect(PlacementTuning.parameterProblems.isEmpty, "\(PlacementTuning.parameterProblems)")
        #expect(PlacementTuning.parameters.map(\.key) == [
            "distance", "belowTheGazeDegrees", "steepestDegrees", "looksAsBigAsAt", "leastLevelGaze",
            "handleWidth", "handleHeight", "handleGap", "handleReachBeyondEnds", "handleReachHeight",
        ])
    }

    @Test func itsDefaultsAreTheSettledNumbers() {
        #expect(PlacementTuning.defaults == .standard)
        #expect(PlacementTuning.defaults.tunedValues.isEmpty)
        #expect(PlacementTuning.swiftName == "PlacementTuning")
    }

    /// Every value tuned away from its default comes back from what's saved.
    @Test func aTunedTuningComesBackFromWhatItSaves() {
        let tuned = PlacementTuning(
            distance: 0.85, belowTheGazeDegrees: 25, steepestDegrees: 50, looksAsBigAsAt: 1.25, leastLevelGaze: 0.15,
            handleWidth: 160, handleHeight: 20, handleGap: 16, handleReachBeyondEnds: 30, handleReachHeight: 72
        )
        #expect(tuned.tunedValues.count == PlacementTuning.parameters.count)
        #expect(PlacementTuning(defaultsTunedWith: tuned.tunedValues) == tuned)
        #expect(tuned.handleSize == SIMD2(160, 20))
    }
}
