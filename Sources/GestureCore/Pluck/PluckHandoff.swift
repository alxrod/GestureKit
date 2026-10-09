import simd

/// The seam where a pluck hands over to a carry. The pluck owns a pinch on
/// an item up to the moment the item breaks free and spawns into the room
/// (`PluckPress.Action.breakFree`), and where it spawns. From then on, the
/// same pinch carries what spawned as a grab handle's pinch carries a
/// thing, by GestureCore's carry (`CarryPinch`): its middle where it spawned
/// plus the hand's translation since, 1:1, in meters in the space it
/// spawned in. The pluck has no movement math of its own past the spawn.
///
/// What stands the carried thing is the carry's and facing's too: its
/// middle kept clear of the viewer's head (`HandCarry`) and turned to face
/// them (`Facing`), both in `HandCarry.pose(carriedTo:clearOf:from:keeping:tuning:facing:)`,
/// or, for an entity, GestureKit's `CarriedEntity.stand`. Once the pinch
/// lets go, the thing is the app's, and a later pinch carries it by a grab
/// handle of its own (`GrabHandleCarry`), as any carried thing.
///
/// - **It begins** as the item spawns, at `spawnedAt`, with the hand at
///   `handAt`, both in meters in the space: its carry has begun, its middle
///   where it spawned. The carry waits for no distance, as the pinch has
///   moved its break-free distance already.
/// - **Each move** of the hand, `handMoved(to:)`, carries the middle to
///   where it spawned plus the hand's translation since, as `CarryPinch`
///   carries a middle. A hand that isn't a place moves nothing.
/// - **Its end**, the pinch let go, ends the carry once (`end()`), the
///   middle where the last move put it.
///
/// `ID` names what spawned as the caller knows it, as `CarryPinch`'s does.
public struct PluckHandoff<ID: Equatable & Sendable>: Equatable, Sendable {
    /// The carry of what spawned, GestureCore's own.
    public private(set) var carry: CarryPinch<ID>
    /// What spawned, as the caller named it.
    public let id: ID
    /// Where it spawned, in meters in the space.
    public let spawnedAt: SIMD3<Float>
    /// Where the hand was as it spawned, in meters in the space.
    public let handAtSpawn: SIMD3<Float>
    /// Where the carry last put the middle: where it spawned until the hand
    /// moves.
    public private(set) var middle: SIMD3<Float>
    /// How far the hand had moved since the spawn at the carry's last step.
    public private(set) var handMoved: SIMD3<Float> = .zero

    /// The handoff of `id`, spawned at `spawnedAt` with the hand at `handAt`,
    /// both in meters in the space, its carry begun. Nil, carrying nothing,
    /// should either not be a place, as a spawn the caller couldn't place.
    public init?(carrying id: ID, spawnedAt: SIMD3<Float>, handAt: SIMD3<Float>) {
        guard Self.isPlace(spawnedAt), Self.isPlace(handAt) else { return nil }
        self.id = id
        self.spawnedAt = spawnedAt
        self.handAtSpawn = handAt
        middle = spawnedAt
        carry = CarryPinch(tuning: CarryTuning(startDistance: 0))
        _ = carry.move(distance: 0, translation: .zero) { .init(id: id, middle: spawnedAt) }
    }

    /// Whether the carry is under way: begun, and not yet ended.
    public var isCarrying: Bool {
        if case .moving = carry.stage { true } else { false }
    }

    /// The hand is at `hand` now, in meters in the space: the carry's step,
    /// the middle where it spawned plus the hand's translation since, 1:1,
    /// as `CarryPinch` says (`CarryPinch.Action.carry`). None once the carry
    /// has ended, or for a hand that isn't a place.
    public mutating func handMoved(to hand: SIMD3<Float>) -> [CarryPinch<ID>.Action] {
        guard Self.isPlace(hand) else { return [] }
        let actions = carry.move(distance: 0, translation: hand - handAtSpawn) { nil }
        for case .carry(_, let middle, let handMoved) in actions {
            self.middle = middle
            self.handMoved = handMoved
        }
        return actions
    }

    /// The pinch let go: the carry ends, once, the middle where its last step
    /// put it (`CarryPinch.Action.endCarry`).
    public mutating func end() -> [CarryPinch<ID>.Action] {
        carry.end()
    }

    /// Whether `vector` is a place: none of it infinite, or not a number.
    private static func isPlace(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }
}
