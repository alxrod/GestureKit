import Foundation

/// One tunable value of a gesture, described so GestureLab's panel can show
/// it, and its store save it, without knowing the gesture: a stable key, a
/// title, a unit, a slider's range and step or a switch, and how to read and
/// write it in the tuning, through its key path. Its default is the one
/// `Tuning.defaults` holds, so the defaults are written once, in the
/// tuning's own declaration.
///
/// The key is the property's name, which the tuning's initializer takes as
/// its label, so the Swift that `Tunable.swiftInitializer()` writes, "Copy
/// tuning" in the lab, compiles; and it's what a tuning is saved under, so
/// renaming a property loses what was saved for it, and nothing else.
///
/// Make one with `number(_:key:title:unit:range:step:)` or
/// `toggle(_:key:title:)`:
///
///     .number(\.nearestToHead, key: "nearestToHead", title: "Nearest to the head",
///             unit: "m", range: 0.1...1, step: 0.01)
public struct TuningParameter<Tuning: Tunable>: Sendable, Identifiable {
    /// How the panel sets a value.
    public enum Control: Sendable, Hashable {
        /// A slider over `range`, in steps of `step` from its lower bound.
        case slider(range: ClosedRange<Double>, step: Double)
        /// A switch.
        case toggle
    }

    /// The property's name: what it's saved under, and its label in the
    /// tuning's initializer.
    public let key: String
    /// What the panel calls it, in a few plain words.
    public let title: String
    /// Its unit as the panel shows it after the number, such as "m", "s",
    /// "pt", or "°"; empty for none, and for a switch.
    public let unit: String
    /// A slider or a switch.
    public let control: Control

    private let read: @Sendable (Tuning) -> TuningValue
    private let write: @Sendable (inout Tuning, TuningValue) -> Void
    private let literal: @Sendable (TuningValue) -> String

    public var id: String { key }

    /// Whether it's a switch rather than a number.
    public var isSwitch: Bool {
        if case .toggle = control { true } else { false }
    }

    /// The slider's range; 0...1 for a switch.
    public var range: ClosedRange<Double> {
        if case .slider(let range, _) = control { range } else { 0...1 }
    }

    /// The slider's step; 1 for a switch.
    public var step: Double {
        if case .slider(_, let step) = control { step } else { 1 }
    }

    /// Its value in `Tuning.defaults`: GestureKit's default.
    public var defaultValue: TuningValue { read(Tuning.defaults) }

    /// Its value in `tuning`.
    public func value(in tuning: Tuning) -> TuningValue { read(tuning) }

    /// Sets it in `tuning` to `value`, fitted to its range and step
    /// (`fitted(_:)`); a value of the other kind, a switch's for a number or
    /// a number's for a switch, changes nothing.
    public func set(_ value: TuningValue, in tuning: inout Tuning) {
        guard let fitted = fitted(value) else { return }
        write(&tuning, fitted)
    }

    /// `value` as this parameter can hold it: a number held within its
    /// range, moved to the nearest step from the range's lower bound, and
    /// rounded to as many decimals as the step and the range's bounds have,
    /// so a slider's 0.30000000000000004 is saved, shown, and copied as 0.3;
    /// a switch as it is; nil for a value of the other kind, or a number
    /// that isn't finite.
    public func fitted(_ value: TuningValue) -> TuningValue? {
        switch (control, value) {
        case (.toggle, .toggle):
            return value
        case (.slider(let range, let step), .number(let number)):
            guard number.isFinite else { return nil }
            return .number(fitTuningNumber(number, to: range, step: step))
        default:
            return nil
        }
    }

    /// `value` as the panel shows it: a number to as many decimals as its
    /// step has, with its unit, "0.30 m", "12 pt", or "45°"; a switch as
    /// "On" or "Off".
    public func text(for value: TuningValue) -> String {
        switch value {
        case .toggle(let isOn):
            return isOn ? "On" : "Off"
        case .number(let number):
            let shown = String(format: "%.\(tuningDecimals(of: step))f", number + 0)
            if unit.isEmpty { return shown }
            return unit == "°" || unit == "%" ? shown + unit : shown + " " + unit
        }
    }

    /// `value` as Swift for the property: `0.35` for a `Double`, `Float`, or
    /// `CGFloat`, `.seconds(0.35)` for a `Duration`, `true` for a `Bool`.
    public func swiftLiteral(for value: TuningValue) -> String { literal(value) }

    private init(
        key: String,
        title: String,
        unit: String,
        control: Control,
        read: @escaping @Sendable (Tuning) -> TuningValue,
        write: @escaping @Sendable (inout Tuning, TuningValue) -> Void,
        literal: @escaping @Sendable (TuningValue) -> String
    ) {
        self.key = key
        self.title = title
        self.unit = unit
        self.control = control
        self.read = read
        self.write = write
        self.literal = literal
    }
}

extension TuningParameter {
    /// A `Double` the panel sets with a slider over `range`, in steps of
    /// `step`.
    public static func number(
        _ keyPath: WritableKeyPath<Tuning, Double> & Sendable,
        key: String,
        title: String,
        unit: String = "",
        range: ClosedRange<Double>,
        step: Double
    ) -> TuningParameter {
        TuningParameter(
            key: key, title: title, unit: unit, control: .slider(range: range, step: step),
            read: { .number($0[keyPath: keyPath]) },
            write: { tuning, value in
                if let number = value.number { tuning[keyPath: keyPath] = number }
            },
            literal: tuningNumberLiteral
        )
    }

    /// A `Float`, as RealityKit's distances are, which the panel sets with a
    /// slider over `range`, in steps of `step`. It reads as the shortest
    /// decimal that is the `Float`, so a default of 0.3 shows, saves, and
    /// copies as 0.3, not 0.30000001192092896.
    public static func number(
        _ keyPath: WritableKeyPath<Tuning, Float> & Sendable,
        key: String,
        title: String,
        unit: String = "",
        range: ClosedRange<Double>,
        step: Double
    ) -> TuningParameter {
        TuningParameter(
            key: key, title: title, unit: unit, control: .slider(range: range, step: step),
            read: { .number(Double("\($0[keyPath: keyPath])") ?? Double($0[keyPath: keyPath])) },
            write: { tuning, value in
                if let number = value.number { tuning[keyPath: keyPath] = Float(number) }
            },
            literal: tuningNumberLiteral
        )
    }

    /// A `CGFloat`, as SwiftUI's points are, which the panel sets with a
    /// slider over `range`, in steps of `step`.
    public static func number(
        _ keyPath: WritableKeyPath<Tuning, CGFloat> & Sendable,
        key: String,
        title: String,
        unit: String = "",
        range: ClosedRange<Double>,
        step: Double
    ) -> TuningParameter {
        TuningParameter(
            key: key, title: title, unit: unit, control: .slider(range: range, step: step),
            read: { .number(Double($0[keyPath: keyPath])) },
            write: { tuning, value in
                if let number = value.number { tuning[keyPath: keyPath] = CGFloat(number) }
            },
            literal: tuningNumberLiteral
        )
    }

    /// A `Duration`, as a gesture's rules time it, which the panel sets in
    /// seconds with a slider over `range`, in steps of `step`.
    public static func number(
        _ keyPath: WritableKeyPath<Tuning, Duration> & Sendable,
        key: String,
        title: String,
        unit: String = "s",
        range: ClosedRange<Double>,
        step: Double
    ) -> TuningParameter {
        TuningParameter(
            key: key, title: title, unit: unit, control: .slider(range: range, step: step),
            read: { .number(tuningSeconds(of: $0[keyPath: keyPath])) },
            write: { tuning, value in
                if let number = value.number { tuning[keyPath: keyPath] = .seconds(number) }
            },
            literal: { ".seconds(\(tuningNumberLiteral($0)))" }
        )
    }

    /// A `Bool` the panel sets with a switch.
    public static func toggle(
        _ keyPath: WritableKeyPath<Tuning, Bool> & Sendable,
        key: String,
        title: String
    ) -> TuningParameter {
        TuningParameter(
            key: key, title: title, unit: "", control: .toggle,
            read: { .toggle($0[keyPath: keyPath]) },
            write: { tuning, value in
                if let isOn = value.isOn { tuning[keyPath: keyPath] = isOn }
            },
            literal: { $0.isOn.map { $0 ? "true" : "false" } ?? "false" }
        )
    }
}

/// A number as a Swift literal: Swift's own shortest form, "0.35" or "2.0".
private func tuningNumberLiteral(_ value: TuningValue) -> String {
    "\(value.number ?? 0)"
}

/// A duration in seconds.
private func tuningSeconds(of duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
}

/// `number` held within `range`, moved to the nearest step from its lower
/// bound, and rounded to as many decimals as the step and the bounds have.
private func fitTuningNumber(_ number: Double, to range: ClosedRange<Double>, step: Double) -> Double {
    var fitted = min(max(number, range.lowerBound), range.upperBound)
    if step > 0 {
        let steps = ((fitted - range.lowerBound) / step).rounded()
        fitted = min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
    }
    let places = max(tuningDecimals(of: step), tuningDecimals(of: range.lowerBound), tuningDecimals(of: range.upperBound))
    let scale = tuningPowersOfTen[places]
    // Adding zero turns -0.0 into 0.0, which shows as "0.00", not "-0.00".
    return (fitted * scale).rounded() / scale + 0
}

/// How many decimals `number` has, up to nine: 2 for 0.25, 0 for 12.
private func tuningDecimals(of number: Double) -> Int {
    guard number.isFinite else { return 0 }
    for places in 0..<tuningPowersOfTen.count - 1 {
        let scaled = number * tuningPowersOfTen[places]
        if abs(scaled - scaled.rounded()) <= 1e-9 * max(1, abs(scaled)) { return places }
    }
    return tuningPowersOfTen.count - 1
}

private let tuningPowersOfTen: [Double] = [1, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9]
