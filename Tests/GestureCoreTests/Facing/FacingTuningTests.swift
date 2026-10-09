import Testing
@testable import GestureCore

/// Facing's tuning as the lab tunes it.
@Suite struct FacingTuningTests {
    @Test func itsParametersAreSound() {
        #expect(FacingTuning.parameterProblems.isEmpty, "\(FacingTuning.parameterProblems)")
        #expect(FacingTuning.parameters.map(\.key) == ["verticalTolerance"])
    }

    @Test func itsDefaultsAreTheSettledNumbers() {
        #expect(FacingTuning.defaults == .standard)
        #expect(FacingTuning.defaults.tunedValues.isEmpty)
        #expect(FacingTuning.swiftName == "FacingTuning")
    }

    @Test func aTunedTuningComesBackFromWhatItSaves() {
        let tuned = FacingTuning(verticalTolerance: 0.0125)
        #expect(tuned.tunedValues == ["verticalTolerance": .number(0.0125)])
        #expect(FacingTuning(defaultsTunedWith: tuned.tunedValues) == tuned)
    }
}
