import Foundation
import Observation

/// The lab's state: its stations, which one is chosen, remembered across
/// launches, and whether the immersive space is open.
@MainActor @Observable
final class LabModel {
    /// The immersive space's id.
    static let spaceID = "lab-space"

    private static let chosenKey = "GestureLab.chosenStation"

    /// Every station, as the registry made them.
    let stations: [any LabStation]

    /// The id of the station the window shows and the space stands.
    var chosenID: String {
        didSet { UserDefaults.standard.set(chosenID, forKey: Self.chosenKey) }
    }

    /// Whether the immersive space is open, as its view says.
    var isSpaceOpen = false

    init(stations: [any LabStation]) {
        precondition(!stations.isEmpty, "The lab needs a station.")
        self.stations = stations
        let remembered = UserDefaults.standard.string(forKey: Self.chosenKey)
        chosenID = stations.contains { $0.id == remembered } ? remembered ?? stations[0].id : stations[0].id
    }

    /// The chosen station.
    var chosen: any LabStation {
        stations.first { $0.id == chosenID } ?? stations[0]
    }
}
