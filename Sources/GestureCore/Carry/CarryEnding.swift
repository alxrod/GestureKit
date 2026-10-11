/// How a carry by a grab handle ended: let go by the person, or taken from
/// them. An app that stands a carried thing where it was let go, and saves
/// that, may want to tell the two apart: a release chose where the thing
/// stands, while a cancel or the view going mid-carry chose nothing, so the
/// app may put it back where it was lifted from instead.
///
/// Its raw values are the words GestureKit's automation answers with
/// (`"ending": "released"`).
public enum CarryEnding: String, Equatable, Hashable, Sendable, CaseIterable, CustomStringConvertible {
    /// The pinch was let go: its gesture ended.
    case released
    /// Its gesture was cancelled: the gesture's state reset with no end, as
    /// when the system takes the pinch away.
    case cancelled
    /// The view the carry's gesture is on went mid-carry, as when its
    /// immersive space closes, or the app shows something else in its place.
    case viewWent

    /// The words a trace or a log gives it: "released", "cancelled, its
    /// gesture reset with no release", or "ended as its view went".
    public var description: String {
        switch self {
        case .released: "released"
        case .cancelled: "cancelled, its gesture reset with no release"
        case .viewWent: "ended as its view went"
        }
    }
}
