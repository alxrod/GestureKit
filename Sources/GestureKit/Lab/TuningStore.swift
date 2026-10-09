#if os(visionOS)
import Foundation
import GestureCore
import Observation
import os

private let logger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "TuningStore")

/// A gesture's tuning as GestureLab tunes it live: observable, so whatever
/// reads `tuning` follows each change as a slider moves, and kept in
/// `UserDefaults` under a namespace, so a launch begins where the last one
/// left off.
///
/// It saves only the values that differ from the defaults
/// (`Tunable.tunedValues`), as JSON under "<namespace>.tuning", so a value
/// no one tuned follows GestureKit's default as that changes, and a saved
/// value is fitted to its parameter as it loads, a key no parameter has
/// passed over.
@MainActor @Observable
public final class TuningStore<Tuning: Tunable> {
    /// The tuning as it stands; setting it saves it.
    public var tuning: Tuning {
        didSet {
            if tuning != oldValue { save() }
        }
    }

    /// What its values are saved under, such as "GestureLab.carry".
    public let namespace: String

    @ObservationIgnored private let defaults: UserDefaults

    /// The tuning saved under `namespace` in `defaults`, or the defaults.
    public init(namespace: String, defaults: UserDefaults = .standard) {
        self.namespace = namespace
        self.defaults = defaults
        tuning = Self.load(from: defaults, key: "\(namespace).tuning")
    }

    /// Sets `parameter` to `value`, fitted to its range and step. A value the
    /// tuning has already changes nothing, and tells no one: each set of
    /// `tuning` draws again whatever reads it, the station's views and the
    /// panel, whether its value changed or not, and a slider dragged within
    /// one step sets the value it has.
    public func set(_ value: TuningValue, for parameter: TuningParameter<Tuning>) {
        var changed = tuning
        parameter.set(value, in: &changed)
        guard changed != tuning else { return }
        tuning = changed
    }

    /// `parameter`'s value as the tuning stands.
    public func value(of parameter: TuningParameter<Tuning>) -> TuningValue {
        parameter.value(in: tuning)
    }

    /// Whether any value differs from its default.
    public var isTuned: Bool { tuning != Tuning.defaults }

    /// Puts every value back to GestureKit's default.
    public func resetToDefaults() {
        tuning = Tuning.defaults
    }

    private var key: String { "\(namespace).tuning" }

    private func save() {
        let values = tuning.tunedValues
        guard !values.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            defaults.set(try encoder.encode(values), forKey: key)
        } catch {
            logger.error("Couldn't save the tuning of \(self.namespace, privacy: .public): \(error)")
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> Tuning {
        guard let data = defaults.data(forKey: key) else { return Tuning.defaults }
        do {
            return Tuning(defaultsTunedWith: try JSONDecoder().decode([String: TuningValue].self, from: data))
        } catch {
            logger.error("Couldn't read the tuning saved under \(key, privacy: .public), so it's back to its defaults: \(error)")
            return Tuning.defaults
        }
    }
}
#endif
