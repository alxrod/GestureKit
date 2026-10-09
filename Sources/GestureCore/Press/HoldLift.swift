import Foundation

/// How something held still lifts as its press picks it up, and on toward its
/// hold, as an item lifts off its grid as it's held: it scales up a little
/// about its middle and comes toward the viewer, out of the plane it stood
/// in. Nothing until the pinch picks up (`SurfacePress.Tuning.pickUpDelay`),
/// so a tap or a drag never shows it; then it pops up to its picked-up look
/// over `Tuning.popDuration`, overshooting a little as a spring with a little
/// bounce does, so the moment it's picked up reads plainly; and on a surface
/// still counting down to its hold, it rises on from there to its held look
/// as the hold fires (`SurfacePress.Tuning.holdDuration`). One that can't
/// hold stays picked up.
///
/// Only what's drawn should lift, inside the view that takes the pinch, so
/// the pinch's points don't move under it as it lifts, and a still pinch
/// stays still.
public enum HoldLift {
    /// The lift's numbers, which the lab tunes live; each default is what
    /// settled on the headset: 5% larger and 2.5 cm nearer picked up, 6% and
    /// 3 cm as the hold fires.
    public struct Tuning: Hashable, Sendable, Codable {
        /// How much larger it shows picked up, about its middle: 5%, most of
        /// the lift, so the pickup is plain, the rest coming as a hold counts
        /// down.
        public var pickedUpScale: Double
        /// How far toward the viewer it stands picked up, in meters: 2.5 cm.
        public var pickedUpDepth: Double
        /// How much larger it shows as its hold fires: 6%, a little less than
        /// a grid item's 8%, as a surface can be a meter wide, so a meter's
        /// grows 3 cm either way.
        public var heldScale: Double
        /// How far toward the viewer it stands as its hold fires, in meters:
        /// 3 cm.
        public var heldDepth: Double
        /// How long the pickup's pop takes, from the moment it picks up to
        /// standing picked up, in seconds: a fifth of a second.
        public var popDuration: Double
        /// How far past its picked-up look the pop goes at its peak, as a
        /// share of the way there: a tenth, as an ease out that backs by
        /// about 1.7, the usual back easing's (`popCurve(_:overshoot:)`).
        public var popOvershoot: Double
        /// How long it takes to settle back down, as the pinch ends, carries,
        /// or holds, in seconds: a spring of 0.32 s with no bounce, so it
        /// never dips behind where it stood.
        public var settleDuration: Double

        /// A lift's tuning, each number its default unless given.
        public init(
            pickedUpScale: Double = 1.05,
            pickedUpDepth: Double = 0.025,
            heldScale: Double = 1.06,
            heldDepth: Double = 0.03,
            popDuration: Double = 0.2,
            popOvershoot: Double = 0.1,
            settleDuration: Double = 0.32
        ) {
            self.pickedUpScale = pickedUpScale
            self.pickedUpDepth = pickedUpDepth
            self.heldScale = heldScale
            self.heldDepth = heldDepth
            self.popDuration = popDuration
            self.popOvershoot = popOvershoot
            self.settleDuration = settleDuration
        }

        /// GestureKit's lift.
        public static let defaults = Tuning()
    }

    /// How it looks lifted: how much larger, about its middle, and how far
    /// toward the viewer, in meters.
    public struct Look: Hashable, Sendable {
        /// How much larger it shows: 1 at rest.
        public var scale: Double
        /// How far toward the viewer it stands, in meters: none at rest.
        public var depth: Double

        public init(scale: Double, depth: Double) {
            self.scale = scale
            self.depth = depth
        }

        /// At rest: as it stands, unlifted.
        public static let rest = Look(scale: 1, depth: 0)
    }

    /// How it looks `elapsed` seconds into a pinch that `isPickedUp`, and
    /// `canStillHold` while it counts down toward its hold, as `press` tunes
    /// it: at rest until its pickup delay; then the pop, up to the picked-up
    /// look, overshooting on the way; then, while it can still hold, rising,
    /// quickly at first, as a quadratic eases out, to the held look at its
    /// hold's duration, and no more after; and otherwise staying picked up.
    /// At rest for a pinch that hasn't picked up, or a time that isn't one.
    public static func look(
        after elapsed: Double,
        isPickedUp: Bool,
        canStillHold: Bool,
        tunedAs press: SurfacePress.Tuning = .defaults
    ) -> Look {
        let lift = press.lift
        guard isPickedUp, elapsed.isFinite, elapsed > press.pickUpDelay else { return .rest }
        let sincePickUp = elapsed - press.pickUpDelay
        var popped = 1.0
        var risen = 0.0
        if sincePickUp < lift.popDuration {
            popped = popCurve(sincePickUp / lift.popDuration, overshoot: lift.popOvershoot)
        } else {
            let rise = press.holdDuration - press.pickUpDelay - lift.popDuration
            if canStillHold, rise > 0 {
                let share = min((sincePickUp - lift.popDuration) / rise, 1)
                risen = 1 - (1 - share) * (1 - share)
            }
        }
        return Look(
            scale: 1 + (lift.pickedUpScale - 1) * popped + (lift.heldScale - lift.pickedUpScale) * risen,
            depth: lift.pickedUpDepth * popped + (lift.heldDepth - lift.pickedUpDepth) * risen
        )
    }

    /// How the pinch `press` looks `elapsed` seconds into it, as its tuning
    /// says (`look(after:isPickedUp:canStillHold:tunedAs:)`).
    public static func look(after elapsed: Double, of press: SurfacePress) -> Look {
        look(after: elapsed, isPickedUp: press.isPickedUp, canStillHold: press.canStillHold, tunedAs: press.tuning)
    }

    /// Whether the lift of the pinch `press` may still change, `elapsed`
    /// seconds into it, so the caller goes on counting its frames: while it
    /// may still pick up, while its pop is under way, and while, picked up,
    /// it counts down toward its hold. A pinch that gave its pickup up, or
    /// stays picked up, changes no more.
    public static func mayChange(after elapsed: Double, of press: SurfacePress) -> Bool {
        guard elapsed.isFinite else { return false }
        if press.canStillPickUp { return true }
        guard press.isPickedUp else { return false }
        if elapsed < press.tuning.pickUpDelay + press.tuning.lift.popDuration { return true }
        return press.canStillHold && elapsed < press.tuning.holdDuration
    }

    /// The pop's curve, from 0 as it begins to 1 as it's done, `share` of the
    /// way through it: an ease out that backs, rising to 1 + `overshoot` a
    /// little past halfway, then settling, as a spring with a little bounce
    /// does; 0 before it, and 1 after. With no overshoot it's an ease out,
    /// cubic, that never passes 1.
    public static func popCurve(_ share: Double, overshoot: Double = Tuning.defaults.popOvershoot) -> Double {
        guard share > 0 else { return 0 }
        guard share < 1 else { return 1 }
        let backing = backing(forOvershoot: overshoot)
        let s = share - 1
        return 1 + (backing + 1) * s * s * s + backing * s * s
    }

    /// The back easing's constant that overshoots by `overshoot` at its peak:
    /// its peak is 1 + 4b³ / (27 (b + 1)²), which rises with b, so it's found
    /// by halving; about 1.7 for a tenth, the usual back easing's 1.70158,
    /// and none for none, or for an overshoot that isn't a number.
    public static func backing(forOvershoot overshoot: Double) -> Double {
        guard overshoot.isFinite, overshoot > 0 else { return 0 }
        let peak = { (b: Double) in 4 * b * b * b / (27 * (b + 1) * (b + 1)) }
        var low = 0.0
        var high = 1.0
        while peak(high) < overshoot, high < 1e6 { high *= 2 }
        for _ in 0..<100 {
            let middle = (low + high) / 2
            if peak(middle) < overshoot { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }
}
