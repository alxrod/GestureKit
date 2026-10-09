/// A gesture's tuning: the values its rules take, as a struct whose
/// defaults are GestureKit's, described so GestureLab can show, change, and
/// save each one without knowing the gesture.
///
/// Each gesture area's tuning conforms. `defaults` is what an app gets
/// unless it passes its own, and `parameters` lists each value the lab's
/// panel shows, in the order it shows them. Give the struct a public
/// initializer that takes each parameter by its key, with the default
/// beside it, so the Swift `swiftInitializer()` writes compiles:
///
///     public struct Tuning: Tunable {
///         /// The nearest a carried thing comes to the viewer's head, in meters.
///         public var nearestToHead: Float
///         /// Whether it turns to face the viewer as it's carried.
///         public var facesTheViewer: Bool
///
///         public init(nearestToHead: Float = 0.3, facesTheViewer: Bool = true) {
///             self.nearestToHead = nearestToHead
///             self.facesTheViewer = facesTheViewer
///         }
///
///         public static let defaults = Tuning()
///
///         public static let parameters: [TuningParameter<Tuning>] = [
///             .number(\.nearestToHead, key: "nearestToHead", title: "Nearest to the head",
///                     unit: "m", range: 0.1...1, step: 0.01),
///             .toggle(\.facesTheViewer, key: "facesTheViewer", title: "Faces the viewer"),
///         ]
///     }
///
/// A test of each tuning should expect `parameterProblems` to be empty.
public protocol Tunable: Sendable, Equatable {
    /// GestureKit's values: what a gesture uses unless it's given others.
    static var defaults: Self { get }

    /// Each value the lab's panel shows and its store saves, in the order
    /// the panel shows them.
    static var parameters: [TuningParameter<Self>] { get }

    /// The type's name as Swift outside its module spells it, which
    /// `swiftInitializer()` begins with: "Carry.Tuning" for
    /// `GestureCore.Carry.Tuning`. The default drops the module's name from
    /// the type's full name.
    static var swiftName: String { get }
}

extension Tunable {
    public static var swiftName: String {
        let reflected = String(reflecting: Self.self)
        // A type in a function, or a generic one, has no plain name to give.
        guard !reflected.contains("("), !reflected.contains("<"),
              let dot = reflected.firstIndex(of: ".") else { return reflected }
        return String(reflected[reflected.index(after: dot)...])
    }

    /// The parameter saved under `key`, if there is one.
    public static func parameter(withKey key: String) -> TuningParameter<Self>? {
        parameters.first { $0.key == key }
    }

    /// The values that differ from the defaults, by key: what the lab's
    /// tuning store saves, so a value no one tuned follows GestureKit's
    /// default as that changes.
    public var tunedValues: [String: TuningValue] {
        var values: [String: TuningValue] = [:]
        for parameter in Self.parameters {
            let value = parameter.value(in: self)
            if value != parameter.defaultValue { values[parameter.key] = value }
        }
        return values
    }

    /// The defaults, with each of `values` set by its key, fitted to its
    /// parameter: a key no parameter has, or a value of the wrong kind, is
    /// passed over, so a tuning saved by an earlier build still loads.
    public init(defaultsTunedWith values: [String: TuningValue]) {
        var tuning = Self.defaults
        for parameter in Self.parameters {
            if let value = values[parameter.key] { parameter.set(value, in: &tuning) }
        }
        self = tuning
    }

    /// Swift that makes this tuning, every parameter by its key, for "Copy
    /// tuning" in the lab, a value that differs from its default marked with
    /// the default it replaces:
    ///
    ///     Carry.Tuning(
    ///         nearestToHead: 0.35, // default 0.3
    ///         facesTheViewer: true
    ///     )
    public func swiftInitializer() -> String {
        let parameters = Self.parameters
        guard !parameters.isEmpty else { return "\(Self.swiftName)()" }
        var lines = ["\(Self.swiftName)("]
        for (index, parameter) in parameters.enumerated() {
            let value = parameter.value(in: self)
            var line = "    \(parameter.key): \(parameter.swiftLiteral(for: value))"
            if index < parameters.count - 1 { line += "," }
            if value != parameter.defaultValue {
                line += " // default \(parameter.swiftLiteral(for: parameter.defaultValue))"
            }
            lines.append(line)
        }
        lines.append(")")
        return lines.joined(separator: "\n")
    }

    /// What's wrong with the parameters' descriptions, a sentence each,
    /// none when they're sound: a key that isn't a Swift identifier, so
    /// can't be the initializer's label, or that two parameters share; an
    /// empty title; a slider whose range is empty or whose step isn't
    /// positive; and a default outside its range, or off its step, which a
    /// slider couldn't come back to.
    public static var parameterProblems: [String] {
        var problems: [String] = []
        var keys: Set<String> = []
        for parameter in parameters {
            let key = parameter.key
            if !isSwiftIdentifier(key) {
                problems.append("The key “\(key)” isn't a Swift identifier, as the initializer's label must be.")
            }
            if !keys.insert(key).inserted {
                problems.append("Two parameters have the key “\(key)”.")
            }
            if parameter.title.isEmpty {
                problems.append("“\(key)” has no title.")
            }
            guard case .slider(let range, let step) = parameter.control else { continue }
            guard range.lowerBound < range.upperBound else {
                problems.append("“\(key)”'s range, \(range), is empty.")
                continue
            }
            guard step > 0 else {
                problems.append("“\(key)”'s step, \(step), isn't positive.")
                continue
            }
            let defaultValue = parameter.defaultValue
            if let number = defaultValue.number, !range.contains(number) {
                problems.append("“\(key)”'s default, \(number), lies outside its range, \(range).")
            } else if parameter.fitted(defaultValue) != defaultValue {
                problems.append("“\(key)”'s default, \(defaultValue), is off its step, \(step).")
            }
        }
        return problems
    }
}

/// Whether `text` can be a Swift argument label: a letter or an underscore,
/// then letters, digits, and underscores.
private func isSwiftIdentifier(_ text: String) -> Bool {
    guard let first = text.unicodeScalars.first else { return false }
    let isLetter = { (scalar: Unicode.Scalar) in
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || scalar == "_"
    }
    return isLetter(first) && text.unicodeScalars.allSatisfy { isLetter($0) || ("0"..."9").contains($0) }
}
