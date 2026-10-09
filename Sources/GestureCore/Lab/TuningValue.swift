/// One tuning value as the lab sees it, whatever the property behind it
/// holds: a number, for a `Double`, `Float`, `CGFloat`, or a `Duration` in
/// seconds, or a switch, for a `Bool`. The lab's panel sets these with its
/// sliders and toggles, and its tuning store saves them, so neither needs to
/// know the gesture.
public enum TuningValue: Sendable, Hashable, Codable, CustomStringConvertible {
    /// A number, in its parameter's unit.
    case number(Double)
    /// A switch, on or off.
    case toggle(Bool)

    /// The number, or nil for a switch.
    public var number: Double? {
        if case .number(let number) = self { number } else { nil }
    }

    /// Whether the switch is on, or nil for a number.
    public var isOn: Bool? {
        if case .toggle(let isOn) = self { isOn } else { nil }
    }

    public var description: String {
        switch self {
        case .number(let number): "\(number)"
        case .toggle(let isOn): isOn ? "true" : "false"
        }
    }

    // Coded as a bare number or Boolean, so a saved tuning reads as plainly
    // as `{"nearestToHead":0.35,"followsHand":false}`.

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let isOn = try? container.decode(Bool.self) {
            self = .toggle(isOn)
        } else {
            self = .number(try container.decode(Double.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let number): try container.encode(number)
        case .toggle(let isOn): try container.encode(isOn)
        }
    }
}
