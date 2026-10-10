import simd
import Testing
@testable import GestureCore

/// The seam between a pluck and a carry: the pluck owns its pinch up to the
/// spawn, and from then on the same pinch carries what spawned by
/// GestureCore's carry, its middle where it spawned plus the hand's
/// translation since, 1:1, stood clear of the head and facing the viewer by
/// the carry's and facing's own rules.
@Suite struct PluckHandoffTests {
    let start = ContinuousClock.now
    let pointsPerMeter = 1360.0
    let spawnedAt = SIMD3<Float>(0.1, 1.3, -0.8)
    let handAt = SIMD3<Float>(0.12, 1.25, -0.6)

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    func isClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, within tolerance: Float = 1e-6) -> Bool {
        simd_distance(a, b) <= tolerance
    }

    // MARK: The handoff

    /// It begins as the item spawns, its carry under way at once, the
    /// middle where it spawned: the carry waits for no distance, the pinch
    /// having gone its break-free distance already.
    @Test func itBeginsWhereTheItemSpawned() throws {
        let handoff = try #require(PluckHandoff(carrying: "item 4", spawnedAt: spawnedAt, handAt: handAt))
        #expect(handoff.isCarrying)
        #expect(handoff.middle == spawnedAt)
        #expect(handoff.handMoved == .zero)
        #expect(handoff.carry.stage == .moving(.init(id: "item 4", middle: spawnedAt)))
    }

    /// Each move of the hand carries the middle where it spawned plus the
    /// hand's translation since, 1:1, as a grab handle's pinch carries a
    /// thing; the hand back where it was puts it back where it spawned.
    @Test func itCarriesTheMiddleOneToOneWithTheHand() throws {
        var handoff = try #require(PluckHandoff(carrying: "item 4", spawnedAt: spawnedAt, handAt: handAt))
        let moved = SIMD3<Float>(0.3, -0.1, 0.25)
        let step = handoff.handMoved(to: handAt + moved)
        #expect(step.count == 1)
        guard case .carry(let id, let middle, let handMoved) = step.first else {
            Issue.record("expected a carry, got \(step)")
            return
        }
        #expect(id == "item 4")
        #expect(isClose(middle, spawnedAt + moved))
        #expect(isClose(handMoved, moved))
        #expect(isClose(handoff.middle, spawnedAt + moved))
        _ = handoff.handMoved(to: handAt)
        #expect(isClose(handoff.middle, spawnedAt))
    }

    /// The pinch let go ends the carry, once, where its last step put the
    /// middle; a move after carries nothing.
    @Test func itEndsOnce() throws {
        var handoff = try #require(PluckHandoff(carrying: 4, spawnedAt: spawnedAt, handAt: handAt))
        _ = handoff.handMoved(to: handAt + SIMD3(0, 0, 0.1))
        #expect(handoff.end() == [.endCarry(id: 4)])
        #expect(!handoff.isCarrying)
        #expect(handoff.end() == [])
        #expect(handoff.handMoved(to: handAt + SIMD3(1, 0, 0)) == [])
        #expect(isClose(handoff.middle, spawnedAt + SIMD3(0, 0, 0.1)))
    }

    /// A hand that isn't a place moves nothing; a spawn or a hand that isn't
    /// a place hands nothing over.
    @Test func whatIsntAPlaceCarriesNothing() throws {
        var handoff = try #require(PluckHandoff(carrying: 4, spawnedAt: spawnedAt, handAt: handAt))
        #expect(handoff.handMoved(to: SIMD3(.nan, 0, 0)) == [])
        #expect(handoff.middle == spawnedAt)
        #expect(PluckHandoff(carrying: 4, spawnedAt: SIMD3(.infinity, 0, 0), handAt: handAt) == nil)
        #expect(PluckHandoff(carrying: 4, spawnedAt: spawnedAt, handAt: SIMD3(0, .nan, 0)) == nil)
    }

    /// What stands the carried thing is the carry's and facing's: the middle
    /// the handoff carries, kept 0.3 m off the head however near the hand
    /// brings it (`HandCarry`), and turned to face the head (`Facing`).
    @Test func theCarryAndFacingStandWhatSpawned() throws {
        let head = SIMD3<Float>(0, 1.6, 0)
        var handoff = try #require(PluckHandoff(carrying: 4, spawnedAt: SIMD3(0, 1.6, -0.5), handAt: SIMD3(0, 1.5, -0.4)))
        _ = handoff.handMoved(to: SIMD3(0, 1.5, -0.1))
        #expect(isClose(handoff.middle, SIMD3(0, 1.6, -0.2)))
        let pose = HandCarry.pose(carriedTo: handoff.middle, clearOf: head, from: SIMD3(0, 1.6, -0.5), keeping: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
        #expect(isClose(pose.position, SIMD3(0, 1.6, -0.3)))
        let facing = Facing.orientation(from: pose.position, toward: head)
        #expect(abs(simd_dot(pose.orientation.vector, facing.vector)) > 1 - 1e-6)
        // Its front, +z, points at the head.
        #expect(isClose(pose.orientation.act(SIMD3(0, 0, 1)), SIMD3(0, 0, 1)))
    }

    // MARK: The pluck hands over at the break-free

    /// A pinch on an item: it lifts, holds, and breaks free, which is where
    /// the pluck's part ends, its item's follow gone. Every move after is
    /// handed to the carry, which carries the middle 1:1 from where it
    /// spawned, and the pinch let go ends the carry, the item settling back
    /// into its container.
    @Test func aPluckHandsOverAtTheBreakFree() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        _ = pinches.armPull(at: at(0.45))
        #expect(pinches.dragMoved(SIMD3(0, 0, 20), pointsPerMeter: pointsPerMeter, at: at(0.5)).actions == [])
        #expect(pinches.follow.z > 0)
        let free = pinches.dragMoved(SIMD3(0, 0, 34), pointsPerMeter: pointsPerMeter, at: at(0.6))
        #expect(free.actions == [.breakFree])
        #expect(pinches.follow == .zero)
        // The caller spawns, and hands over.
        var handoff = try #require(PluckHandoff(carrying: 7, spawnedAt: spawnedAt, handAt: handAt))

        let moved = pinches.dragMoved(SIMD3(80, -40, 120), pointsPerMeter: pointsPerMeter, at: at(0.8))
        #expect(moved.actions == [.carrySpawned])
        #expect(moved.why == .handedToTheCarry)
        #expect(pinches.follow == .zero)
        let hand = SIMD3<Float>(0.06, 0.03, 0.06)
        let step = handoff.handMoved(to: handAt + hand)
        guard step.count == 1, case .carry(7, let middle, let handMoved) = step[0] else {
            Issue.record("expected a carry of 7, got \(step)")
            return
        }
        #expect(isClose(middle, spawnedAt + hand))
        #expect(isClose(handMoved, hand))

        let letGo = pinches.dragEnded(at: at(1.1))
        #expect(letGo.actions == [.releaseSpawned, .settle])
        #expect(handoff.end() == [.endCarry(id: 7)])
        let account = try #require(pinches.pressEnded(at: at(1.1)).ended)
        #expect(account.outcome == .pull)
        #expect(account.pulledAfter == .seconds(0.6))
        #expect(account.farthestStretch == 34)
    }

    /// The pull's drag cancelled after the spawn takes what spawned away.
    @Test func aCancelAfterTheSpawnTakesItAway() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        _ = pinches.armPull(at: at(0.45))
        _ = pinches.dragMoved(SIMD3(40, 0, 0), pointsPerMeter: pointsPerMeter, at: at(0.6))
        #expect(pinches.dragCancelled(at: at(0.7)).actions == [.cancelSpawn, .settle])
    }
}
