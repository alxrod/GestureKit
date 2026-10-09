import Foundation
import GestureCore
import Testing

/// A tuning with one parameter of each kind the lab can tune.
struct SampleTuning: Tunable {
    var distance: Double = 0.3
    var lift: Float = 0.004
    var margin: CGFloat = 10
    var hold: Duration = .milliseconds(500)
    var turn: Double = 45
    var facesTheViewer = true

    static let defaults = SampleTuning()

    static let parameters: [TuningParameter<SampleTuning>] = [
        .number(\.distance, key: "distance", title: "Distance", unit: "m", range: 0.1...1, step: 0.01),
        .number(\.lift, key: "lift", title: "Lift", unit: "m", range: 0...0.02, step: 0.001),
        .number(\.margin, key: "margin", title: "Margin", unit: "pt", range: 0...40, step: 1),
        .number(\.hold, key: "hold", title: "Hold", range: 0.1...2, step: 0.05),
        .number(\.turn, key: "turn", title: "Turn", unit: "°", range: 0...90, step: 5),
        .toggle(\.facesTheViewer, key: "facesTheViewer", title: "Faces the viewer"),
    ]
}

/// A tuning nested in a namespace, as a gesture area's is.
enum SampleGesture {
    struct Tuning: Tunable {
        var reach: Double = 1
        static let defaults = Tuning()
        static let parameters: [TuningParameter<Tuning>] = [
            .number(\.reach, key: "reach", title: "Reach", unit: "m", range: 0...2, step: 0.5),
        ]
    }
}

/// A tuning whose descriptions are wrong in every way `parameterProblems`
/// looks for.
struct FaultyTuning: Tunable {
    var a: Double = 0.5
    var b: Double = 3
    var c: Double = 0.33
    var d: Double = 1
    var e = false

    static let defaults = FaultyTuning()

    static let parameters: [TuningParameter<FaultyTuning>] = [
        .number(\.a, key: "2a", title: "A", range: 0...1, step: 0.1),
        .number(\.b, key: "b", title: "B", range: 0...1, step: 0.1),
        .number(\.c, key: "c", title: "C", range: 0...1, step: 0.1),
        .number(\.d, key: "d", title: "", range: 1...1, step: 0.1),
        .toggle(\.e, key: "b", title: "E"),
    ]
}

@Suite("Tuning")
struct TuningTests {
    @Test("A sound tuning has no problems")
    func soundTuning() {
        #expect(SampleTuning.parameterProblems.isEmpty)
        #expect(SampleGesture.Tuning.parameterProblems.isEmpty)
    }

    @Test("Each problem a tuning's descriptions can have is found")
    func faultyTuning() {
        #expect(FaultyTuning.parameterProblems == [
            "The key “2a” isn't a Swift identifier, as the initializer's label must be.",
            "“b”'s default, 3.0, lies outside its range, 0.0...1.0.",
            "“c”'s default, 0.33, is off its step, 0.1.",
            "“d” has no title.",
            "“d”'s range, 1.0...1.0, is empty.",
            "Two parameters have the key “b”.",
        ])
    }

    @Test("A parameter describes itself for the panel")
    func descriptions() throws {
        let distance = try #require(SampleTuning.parameter(withKey: "distance"))
        #expect(distance.title == "Distance")
        #expect(distance.unit == "m")
        #expect(distance.range == 0.1...1)
        #expect(distance.step == 0.01)
        #expect(!distance.isSwitch)
        #expect(distance.defaultValue == .number(0.3))

        let faces = try #require(SampleTuning.parameter(withKey: "facesTheViewer"))
        #expect(faces.isSwitch)
        #expect(faces.defaultValue == .toggle(true))
        #expect(SampleTuning.parameter(withKey: "nothing") == nil)
    }

    @Test("Defaults read as the numbers they were written as, whatever the property's type")
    func defaultsRead() {
        let defaults = SampleTuning.parameters.map(\.defaultValue)
        #expect(defaults == [.number(0.3), .number(0.004), .number(10), .number(0.5), .number(45), .toggle(true)])
    }

    @Test("A number set is held within its range, on its step, and rounded to the step's decimals")
    func fitting() throws {
        let distance = try #require(SampleTuning.parameter(withKey: "distance"))
        var tuning = SampleTuning.defaults
        distance.set(.number(0.1 + 0.2 + 0.05), in: &tuning)
        #expect(tuning.distance == 0.35)
        distance.set(.number(0.123), in: &tuning)
        #expect(tuning.distance == 0.12)
        distance.set(.number(5), in: &tuning)
        #expect(tuning.distance == 1)
        distance.set(.number(-1), in: &tuning)
        #expect(tuning.distance == 0.1)
        distance.set(.number(.nan), in: &tuning)
        #expect(tuning.distance == 0.1)
        distance.set(.toggle(true), in: &tuning)
        #expect(tuning.distance == 0.1)
    }

    @Test("A Float, a CGFloat, and a Duration are set through the number")
    func otherTypes() throws {
        var tuning = SampleTuning.defaults
        try #require(SampleTuning.parameter(withKey: "lift")).set(.number(0.0071), in: &tuning)
        #expect(tuning.lift == 0.007)
        try #require(SampleTuning.parameter(withKey: "margin")).set(.number(12.4), in: &tuning)
        #expect(tuning.margin == 12)
        let hold = try #require(SampleTuning.parameter(withKey: "hold"))
        hold.set(.number(0.73), in: &tuning)
        #expect(hold.value(in: tuning) == .number(0.75))
        #expect(tuning.hold == .milliseconds(750))
        let faces = try #require(SampleTuning.parameter(withKey: "facesTheViewer"))
        faces.set(.toggle(false), in: &tuning)
        #expect(tuning.facesTheViewer == false)
        faces.set(.number(1), in: &tuning)
        #expect(tuning.facesTheViewer == false)
    }

    @Test("Only the values that differ from the defaults are tuned")
    func tunedValues() {
        #expect(SampleTuning.defaults.tunedValues.isEmpty)
        var tuning = SampleTuning.defaults
        tuning.distance = 0.35
        tuning.facesTheViewer = false
        #expect(tuning.tunedValues == ["distance": .number(0.35), "facesTheViewer": .toggle(false)])
    }

    @Test("A tuning is made again from its tuned values, passing over what no parameter takes")
    func remade() {
        var tuning = SampleTuning.defaults
        tuning.distance = 0.35
        tuning.lift = 0.01
        tuning.facesTheViewer = false
        #expect(SampleTuning(defaultsTunedWith: tuning.tunedValues) == tuning)

        let saved: [String: TuningValue] = [
            "distance": .number(7),
            "lift": .toggle(true),
            "gone": .number(1),
        ]
        var expected = SampleTuning.defaults
        expected.distance = 1
        #expect(SampleTuning(defaultsTunedWith: saved) == expected)
    }

    @Test("Tuned values are coded as bare numbers and Booleans")
    func coding() throws {
        let values: [String: TuningValue] = ["distance": .number(0.35), "facesTheViewer": .toggle(false)]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(values)
        #expect(String(decoding: data, as: UTF8.self) == #"{"distance":0.35,"facesTheViewer":false}"#)
        #expect(try JSONDecoder().decode([String: TuningValue].self, from: data) == values)
    }

    @Test("A value shows to its step's decimals, with its unit")
    func text() {
        let texts = SampleTuning.parameters.map { $0.text(for: $0.defaultValue) }
        #expect(texts == ["0.30 m", "0.004 m", "10 pt", "0.50 s", "45°", "On"])
        #expect(SampleTuning.parameters[0].text(for: .number(-0.0)) == "0.00 m")
    }

    @Test("Copy tuning writes Swift that makes the tuning, marking what differs from the defaults")
    func swiftInitializer() {
        var tuning = SampleTuning.defaults
        tuning.distance = 0.35
        tuning.hold = .milliseconds(800)
        tuning.facesTheViewer = false
        #expect(tuning.swiftInitializer() == """
            SampleTuning(
                distance: 0.35, // default 0.3
                lift: 0.004,
                margin: 10.0,
                hold: .seconds(0.8), // default .seconds(0.5)
                turn: 45.0,
                facesTheViewer: false // default true
            )
            """)
    }

    @Test("A tuning's Swift name leaves out its module")
    func swiftName() {
        #expect(SampleTuning.swiftName == "SampleTuning")
        #expect(SampleGesture.Tuning.swiftName == "SampleGesture.Tuning")
        #expect(SampleGesture.Tuning.defaults.swiftInitializer() == "SampleGesture.Tuning(\n    reach: 1.0\n)")
    }
}
