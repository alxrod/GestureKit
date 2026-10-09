/// Every station GestureLab offers, in the order its window lists them:
/// the one place a gesture area adds its station, one line each.
enum LabStations {
    @MainActor static func all() -> [any LabStation] {
        [
            TraceCheckStation(),
            PressStation(),
        ]
    }
}
