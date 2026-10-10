import Foundation
import Observation

/// The lab's state: its stations, which one is chosen, remembered across
/// launches, whether the immersive space is open, and which stations trace
/// what their gestures do, also remembered.
@MainActor @Observable
final class LabModel {
    /// The immersive space's id.
    static let spaceID = "lab-space"

    /// The id of the window group a station's own window opens in, by the
    /// station's id.
    static let stationWindowID = "station-window"

    private static let chosenKey = "GestureLab.chosenStation"
    private static let tracesKey = "GestureLab.traces"
    private static let untracedKey = "GestureLab.untracedStations"

    /// Every station, as the registry made them.
    let stations: [any LabStation]

    /// The id of the station the window shows and the space stands.
    var chosenID: String {
        didSet { UserDefaults.standard.set(chosenID, forKey: Self.chosenKey) }
    }

    /// Whether the immersive space is open, as its view says.
    var isSpaceOpen = false

    /// Whether any station traces what its gestures do. Off, none does, so
    /// the gestures can be felt with no trace at all: their adapters are
    /// handed recorders that give no trace, and do no tracing work. On, each
    /// traces unless its own switch is off (`traces(station:)`).
    var tracesAnything: Bool {
        didSet {
            UserDefaults.standard.set(tracesAnything, forKey: Self.tracesKey)
            applyTracing()
        }
    }

    /// The stations whose own switch has turned their tracing off.
    private var untracedStations: Set<String> {
        didSet {
            UserDefaults.standard.set(untracedStations.sorted(), forKey: Self.untracedKey)
            applyTracing()
        }
    }

    init(stations: [any LabStation]) {
        precondition(!stations.isEmpty, "The lab needs a station.")
        self.stations = stations
        var remembered = UserDefaults.standard.string(forKey: Self.chosenKey)
        #if DEBUG
        // `-station <id>` at launch chooses that station, as for measuring
        // one in the simulator, where nothing can be pinched to choose it.
        if let asked = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["station"] as? String {
            remembered = asked
        }
        #endif
        chosenID = stations.contains { $0.id == remembered } ? remembered ?? stations[0].id : stations[0].id
        var tracesAnything = UserDefaults.standard.object(forKey: Self.tracesKey) as? Bool ?? true
        #if DEBUG
        // `-labTracing off` or `on` at launch, for measuring the lab with
        // tracing off or on in the simulator.
        if let asked = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["labTracing"] as? String {
            tracesAnything = asked != "off"
        }
        #endif
        self.tracesAnything = tracesAnything
        untracedStations = Set(UserDefaults.standard.stringArray(forKey: Self.untracedKey) ?? [])
        applyTracing()
    }

    /// Whether the station `id`'s own switch lets it trace; it does only
    /// while `tracesAnything` is on too.
    func traces(station id: String) -> Bool {
        !untracedStations.contains(id)
    }

    /// Turns the station `id`'s own tracing on or off.
    func setTraces(_ traces: Bool, station id: String) {
        if traces {
            untracedStations.remove(id)
        } else {
            untracedStations.insert(id)
        }
    }

    /// Each station's recorder records while both switches let it.
    private func applyTracing() {
        for station in stations {
            station.trace.isRecording = tracesAnything && traces(station: station.id)
        }
    }

    /// The chosen station.
    var chosen: any LabStation {
        stations.first { $0.id == chosenID } ?? stations[0]
    }

    /// The station with `id`, if there is one.
    func station(withID id: String) -> (any LabStation)? {
        stations.first { $0.id == id }
    }
}
