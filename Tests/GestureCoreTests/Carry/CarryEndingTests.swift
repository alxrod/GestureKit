import Testing
@testable import GestureCore

/// How a carry ended, in the words GestureKit's automation answers with and
/// a trace or a log gives.
@Suite struct CarryEndingTests {
    /// Its raw values are the automation's words, which agents assert on, so
    /// they stay as they are.
    @Test func itsRawValuesAreTheAutomationsWords() {
        #expect(CarryEnding.allCases.map(\.rawValue) == ["released", "cancelled", "viewWent"])
        #expect(CarryEnding(rawValue: "cancelled") == .cancelled)
        #expect(CarryEnding(rawValue: "view went") == nil)
    }

    /// A trace or a log says how a carry ended in a few plain words.
    @Test func itSaysHowACarryEndedInPlainWords() {
        #expect(String(describing: CarryEnding.released) == "released")
        #expect(String(describing: CarryEnding.cancelled) == "cancelled, its gesture reset with no release")
        #expect(String(describing: CarryEnding.viewWent) == "ended as its view went")
    }
}
