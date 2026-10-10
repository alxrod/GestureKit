#if DEBUG
import Foundation

/// Something a command couldn't do, said in a sentence an agent can act on:
/// "No item titled “item 70” is on screen; scroll its grid to it first."
public struct AutomationError: Error, Sendable, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// A command as an agent sent it: its name and its arguments, read
/// leniently, since a shell builds them as strings: a number may come as
/// `0.5` or `"0.5"`, a switch as `true`, `"true"`, `"yes"`, or `1`, and a
/// vector as `[0, 0, 0.05]` or `"0,0,0.05"`. A key the command doesn't take
/// is refused, naming the ones it does, so a misspelled argument never goes
/// unnoticed.
///
///     let arguments = try AutomationArguments(["command": "pluck", "item": "item 7", "pull": "0,0,0.06"])
///     try arguments.vector("pull")   // SIMD3(0, 0, 0.06)
public struct AutomationArguments: Sendable {
    /// The command's name, as sent.
    public let command: String
    /// Its arguments, every member but `command`.
    public let values: [String: AutomationJSON]

    /// The command `json` names, with the rest of its members as arguments;
    /// it must be an object with a `command` string.
    public init(_ json: AutomationJSON) throws {
        guard case .object(var object) = json else {
            throw AutomationError("A command is a JSON object, such as {\"command\": \"state\"}.")
        }
        guard let command = object.removeValue(forKey: "command")?.string, !command.isEmpty else {
            throw AutomationError("A command needs its name, as {\"command\": \"pluck\", \"item\": \"item 7\"}; \"help\" lists them.")
        }
        self.command = command
        values = object
    }

    /// Refuses any argument not among `keys`, naming those it takes.
    public func refuseOthers(than keys: [String]) throws {
        let unknown = values.keys.filter { !keys.contains($0) }.sorted()
        guard !unknown.isEmpty else { return }
        let takes = keys.isEmpty ? "no arguments" : keys.joined(separator: ", ")
        throw AutomationError("\(command) doesn't take \(unknown.joined(separator: ", ")); it takes \(takes).")
    }

    /// Whether `key` was given, as anything but null.
    public func has(_ key: String) -> Bool {
        if let value = values[key], value != .null { true } else { false }
    }

    /// The string under `key`: a number or a switch as its text; nil when
    /// it's missing.
    public func string(_ key: String) throws -> String? {
        switch values[key] {
        case nil, .null?: return nil
        case .string(let string)?: return string
        case .number(let number)?: return AutomationJSON.number(number).text()
        case .bool(let bool)?: return bool ? "true" : "false"
        case .array?, .object?: throw AutomationError("\(command)'s \(key) is a string, such as \"item 7\".")
        }
    }

    /// The string under `key`, which the command needs.
    public func requiredString(_ key: String, example: String) throws -> String {
        guard let string = try string(key), !string.isEmpty else {
            throw AutomationError("\(command) needs \(key), such as \(key)=\"\(example)\".")
        }
        return string
    }

    /// The number under `key`, given as one or as its text; nil when it's
    /// missing.
    public func number(_ key: String) throws -> Double? {
        switch values[key] {
        case nil, .null?: return nil
        case .number(let number)?: return number
        case .string(let text)?:
            guard let number = Double(text.trimmingCharacters(in: .whitespaces)), number.isFinite else {
                throw AutomationError("\(command)'s \(key) is a number, not “\(text)”.")
            }
            return number
        default: throw AutomationError("\(command)'s \(key) is a number.")
        }
    }

    /// The switch under `key`: `true`, `false`, their text, "yes", "no", 1,
    /// or 0; nil when it's missing.
    public func bool(_ key: String) throws -> Bool? {
        switch values[key] {
        case nil, .null?: return nil
        case .bool(let bool)?: return bool
        case .number(let number)?:
            guard number == 0 || number == 1 else { break }
            return number == 1
        case .string(let text)?:
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "on", "1": return true
            case "false", "no", "off", "0": return false
            default: break
            }
        default: break
        }
        throw AutomationError("\(command)'s \(key) is true or false.")
    }

    /// The vector under `key`: three numbers, as an array or as their text
    /// with commas, "0,0,0.05"; nil when it's missing.
    public func vector(_ key: String) throws -> SIMD3<Double>? {
        let parts: [Double]
        switch values[key] {
        case nil, .null?: return nil
        case .array(let array)?:
            parts = try array.map { element in
                guard let number = element.number else { throw vectorError(key) }
                return number
            }
        case .string(let text)?:
            parts = try text.split(separator: ",").map { part in
                guard let number = Double(part.trimmingCharacters(in: .whitespaces)) else { throw vectorError(key) }
                return number
            }
        default: throw vectorError(key)
        }
        guard parts.count == 3, parts.allSatisfy(\.isFinite) else { throw vectorError(key) }
        return SIMD3(parts[0], parts[1], parts[2])
    }

    /// The object under `key`; nil when it's missing.
    public func object(_ key: String) -> [String: AutomationJSON]? {
        values[key]?.object
    }

    private func vectorError(_ key: String) -> AutomationError {
        AutomationError("\(command)'s \(key) is three numbers in meters, x right, y up, z toward you, as [0, 0, 0.05] or \"0,0,0.05\".")
    }
}
#endif
