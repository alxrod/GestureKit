import simd

/// One pinch on a grab handle, from its touch to its end, as an
/// entity-targeted drag on the handle reports it: it carries the thing the
/// handle is under by its middle, 1:1 with the hand, as PhotoFinder's drag
/// carries a picture. That drag was chosen after four were tried side by
/// side on the headset, as the only one that followed the hand.
///
/// - **It waits** until it has moved `tuning.startDistance`, 8 pt, from
///   where it touched, as its gesture measures it: let go sooner, it
///   carries nothing.
/// - **Then it begins** a carry of the thing its handle is under, which the
///   caller finds then and only then (`Grabbed`): named by its id then, from
///   where its middle is then (`Action.beginCarry`), and carries the middle
///   at once. A handle under nothing, as one whose thing has gone, carries
///   nothing for the rest of the pinch (`Action.ignore`), nor does one whose
///   carry the caller couldn't begin (`refuse()`).
/// - **Moving**, each change carries the middle to where it was as the carry
///   began plus the hand's translation since the touch, converted into the
///   space the thing stands in, 1:1, as PhotoFinder adds its drag's
///   translation to where its picture was (`Action.carry`). Where the middle
///   is now doesn't count, so the hand back where it touched puts the thing
///   back where it was.
/// - **Its end**, released or cancelled, ends the carry
///   (`Action.endCarry`). Whichever of the release and the gesture's reset
///   comes first ends it; once it has ended, it does nothing more, so a
///   pinch after it begins afresh.
///
/// A change that isn't a number moves nothing.
///
/// `ID` names the carried thing as the caller knows it, so one kind of
/// pinch carries whatever stands under a handle: a group of items by its
/// first, one item lifted out of a row, a panel by its name.
public struct CarryPinch<ID: Equatable & Sendable>: Equatable, Sendable {
    /// The thing a pinch grabbed, which the caller finds under its handle as
    /// the pinch first moves far enough.
    public struct Grabbed: Equatable, Sendable {
        /// What it was then, which names the carry throughout.
        public var id: ID
        /// Where its middle was then, the point the hand carries it by, in
        /// meters in the space it stands in.
        public var middle: SIMD3<Float>

        public init(id: ID, middle: SIMD3<Float>) {
            self.id = id
            self.middle = middle
        }
    }

    /// What the pinch has come to.
    public enum Stage: Equatable, Sendable {
        /// It hasn't moved `tuning.startDistance` yet.
        case waiting
        /// It carries the thing it grabbed, from where its middle was then.
        case moving(Grabbed)
        /// It carries nothing until it ends.
        case ignored
        /// Ended, released or cancelled.
        case over
    }

    /// What the caller does as the pinch is told.
    public enum Action: Equatable, Sendable {
        /// Begin a carry of the thing named `id`.
        case beginCarry(id: ID)
        /// Carry the middle of the thing named `id` to `middle`, in meters in
        /// the space it stands in, the hand having moved `handMoved` since
        /// the pinch touched.
        case carry(id: ID, middle: SIMD3<Float>, handMoved: SIMD3<Float>)
        /// The pinch moved far enough, but its handle is under nothing: the
        /// rest of it carries nothing.
        case ignore
        /// End the carry of the thing named `id`.
        case endCarry(id: ID)
    }

    /// The numbers the pinch goes by.
    public let tuning: CarryTuning

    /// What the pinch has come to so far.
    public private(set) var stage = Stage.waiting

    public init(tuning: CarryTuning = .standard) {
        self.tuning = tuning
    }

    /// The pinch moved: `distance` points from where it touched, as its
    /// gesture measures them, and `translation` meters in the space since
    /// then. Waiting, it begins once that's `tuning.startDistance`, grabbing
    /// the thing `grab` finds under its handle, asked then and only then,
    /// and is ignored if there's none. Moving, it carries the middle.
    public mutating func move(distance: Double, translation: SIMD3<Float>, grab: () -> Grabbed?) -> [Action] {
        switch stage {
        case .waiting:
            guard distance.isFinite, distance >= tuning.startDistance, Self.isPlace(translation) else { return [] }
            guard let grabbed = grab() else {
                stage = .ignored
                return [.ignore]
            }
            stage = .moving(grabbed)
            return [.beginCarry(id: grabbed.id), Self.carry(grabbed, by: translation)]
        case .moving(let grabbed):
            guard Self.isPlace(translation) else { return [] }
            return [Self.carry(grabbed, by: translation)]
        case .ignored, .over:
            return []
        }
    }

    /// The carry the pinch began couldn't begin, as the caller found: the
    /// rest of the pinch carries nothing, and its end ends nothing.
    public mutating func refuse() {
        guard case .moving = stage else { return }
        stage = .ignored
    }

    /// The pinch ended, released or cancelled: a carry it began ends.
    public mutating func end() -> [Action] {
        let was = stage
        stage = .over
        guard case .moving(let grabbed) = was else { return [] }
        return [.endCarry(id: grabbed.id)]
    }

    /// Carries the middle of `grabbed` from where it was as the carry began
    /// by `translation`, 1:1.
    private static func carry(_ grabbed: Grabbed, by translation: SIMD3<Float>) -> Action {
        .carry(id: grabbed.id, middle: grabbed.middle + translation, handMoved: translation)
    }

    /// Whether `vector` is a place: none of it infinite, or not a number.
    private static func isPlace(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }
}
