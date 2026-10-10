#if DEBUG
import Foundation

/// A JSON value, as GestureKit's automation reads a command and answers it
/// (`GestureAutomation`): plain, `Sendable`, and comparable, so a command's
/// answer can be built on the main actor and handed to the server's queue,
/// and a test can say what it expects.
///
/// It's coded as the JSON it is, an object's keys sorted as it's written, so
/// two answers that say the same thing read the same:
///
///     let answer: AutomationJSON = ["ok": true, "outcome": "spawned", "at": .vector(SIMD3(0.1, 1.2, -0.9))]
///     answer.encoded()   // {"at":[0.1,1.2,-0.9],"ok":true,"outcome":"spawned"}
///
/// Debug builds only, for driving the gestures without a hand.
public enum AutomationJSON: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AutomationJSON])
    case object([String: AutomationJSON])

    /// A number rounded to `decimals`, so a place reads as "0.12", not
    /// "0.12000000476837158": a number that isn't finite is null.
    public static func number(_ value: Double, decimals: Int) -> AutomationJSON {
        guard value.isFinite else { return .null }
        let scale = pow(10, Double(max(0, decimals)))
        return .number((value * scale).rounded() / scale)
    }

    /// A point or a move as three numbers, x, y, and z, to the tenth of a
    /// millimeter in meters, or to `decimals`.
    public static func vector(_ value: SIMD3<Float>, decimals: Int = 4) -> AutomationJSON {
        vector(SIMD3<Double>(value), decimals: decimals)
    }

    /// A point or a move as three numbers, x, y, and z, to `decimals`.
    public static func vector(_ value: SIMD3<Double>, decimals: Int = 4) -> AutomationJSON {
        .array([number(value.x, decimals: decimals), number(value.y, decimals: decimals), number(value.z, decimals: decimals)])
    }

    /// An optional point as a vector, or null.
    public static func vector(_ value: SIMD3<Float>?) -> AutomationJSON {
        value.map { vector($0) } ?? .null
    }

    /// The value under `key`, for an object; nil otherwise, or for no such
    /// key.
    public subscript(key: String) -> AutomationJSON? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    /// The string, or nil for anything else.
    public var string: String? {
        if case .string(let string) = self { string } else { nil }
    }

    /// The number, or nil for anything else.
    public var number: Double? {
        if case .number(let number) = self { number } else { nil }
    }

    /// The switch, or nil for anything else.
    public var bool: Bool? {
        if case .bool(let bool) = self { bool } else { nil }
    }

    /// The elements, or nil for anything but an array.
    public var array: [AutomationJSON]? {
        if case .array(let array) = self { array } else { nil }
    }

    /// The members, or nil for anything but an object.
    public var object: [String: AutomationJSON]? {
        if case .object(let object) = self { object } else { nil }
    }

    /// The JSON it is, keys sorted, and, `pretty`, indented, as a person
    /// reading `curl`'s output would want it.
    public func encoded(pretty: Bool = false) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }

    /// The JSON it is, as text.
    public func text(pretty: Bool = false) -> String {
        String(decoding: encoded(pretty: pretty), as: UTF8.self)
    }

    /// The value `data` holds as JSON.
    public static func decoded(from data: Data) throws -> AutomationJSON {
        try JSONDecoder().decode(AutomationJSON.self, from: data)
    }
}

extension AutomationJSON: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AutomationJSON].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AutomationJSON].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        case .number(let number):
            // A whole number as an integer, so a count reads "3", not "3.0".
            if number.rounded() == number, abs(number) < 1e15 {
                try container.encode(Int64(number))
            } else {
                try container.encode(number)
            }
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }
}

extension AutomationJSON: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: AutomationJSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, AutomationJSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
#endif
