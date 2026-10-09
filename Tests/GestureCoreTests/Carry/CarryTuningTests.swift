import Testing
@testable import GestureCore

/// The carry's tuning as the lab tunes it.
@Suite struct CarryTuningTests {
    @Test func itsParametersAreSound() {
        #expect(CarryTuning.parameterProblems.isEmpty, "\(CarryTuning.parameterProblems)")
        #expect(CarryTuning.parameters.map(\.key) == ["startDistance", "nearestToHead"])
    }

    /// Its defaults are the numbers the carry was settled on with, and none
    /// of them reads as tuned.
    @Test func itsDefaultsAreTheSettledNumbers() {
        #expect(CarryTuning.defaults == .standard)
        #expect(CarryTuning.defaults.tunedValues.isEmpty)
        #expect(CarryTuning.swiftName == "CarryTuning")
    }

    /// A tuning saved as the values that differ from the defaults comes back
    /// as it was, a Float's tenths and hundredths included.
    @Test func aTunedTuningComesBackFromWhatItSaves() {
        let tuned = CarryTuning(startDistance: 12, nearestToHead: 0.45)
        #expect(tuned.tunedValues == ["startDistance": .number(12), "nearestToHead": .number(0.45)])
        #expect(CarryTuning(defaultsTunedWith: tuned.tunedValues) == tuned)
        #expect(tuned.swiftInitializer() == """
            CarryTuning(
                startDistance: 12.0, // default 8.0
                nearestToHead: 0.45 // default 0.3
            )
            """)
    }
}
