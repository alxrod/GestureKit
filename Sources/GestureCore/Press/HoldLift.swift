/// How something held still lifts as its press picks it up, and on toward its
/// hold, as an item lifts off its grid as it's held: it scales up a little
/// about its middle and comes toward the viewer, out of the plane it stood
/// in. Nothing until the pinch picks up (`SurfacePress.Tuning.pickUpDelay`),
/// so a tap or a drag never shows it; then it pops up to `pickedUpShare` of
/// its lift over `popDuration`, overshooting a little as a spring with a
/// little bounce does, so the moment it's picked up reads plainly; and on a
/// surface still counting down to its hold, it rises on from there to all of
/// it as the hold fires (`SurfacePress.Tuning.holdDuration`). One that can't
/// hold stays picked up.
///
/// Only what's drawn should lift, inside the view that takes the pinch, so
/// the pinch's points don't move under it as it lifts, and a still pinch
/// stays still.
public enum HoldLift {
    /// The lift's numbers, which the lab tunes live; each default is what
    /// settled on the headset.
    public struct Tuning: Hashable, Sendable, Codable {
        /// How much of its whole lift it shows picked up: five sixths, 5%
        /// larger and 2.5 cm nearer at the defaults, most of the lift, so the
        /// pickup is plain, the rest coming as a hold counts down.
        public var pickedUpShare: Double
        /// How long the pickup's pop takes, from the moment it picks up to
        /// standing picked up, in seconds: a fifth of a second.
        public var popDuration: Double
        /// How far the pop overshoots on the way, as an ease out that backs
        /// (`popCurve(_:overshoot:)`): 1.70158, the usual back easing's,
        /// which overshoots by about a tenth.
        public var popOvershoot: Double
        /// How much larger it shows lifted all the way, about its middle: 6%,
        /// a little less than a grid item's 8%, as a surface can be a meter
        /// wide, so a meter's grows 3 cm either way.
        public var fullScale: Double
        /// How far toward the viewer it stands lifted all the way, in meters:
        /// 3 cm.
        public var fullDepth: Double

        /// A lift's tuning, each number its default unless given.
        public init(
            pickedUpShare: Double = 5.0 / 6.0,
            popDuration: Double = 0.2,
            popOvershoot: Double = 1.70158,
            fullScale: Double = 1.06,
            fullDepth: Double = 0.03
        ) {
            self.pickedUpShare = pickedUpShare
            self.popDuration = popDuration
            self.popOvershoot = popOvershoot
            self.fullScale = fullScale
            self.fullDepth = fullDepth
        }
    }

    /// How far the lift has come, from 0 at rest to 1 as the hold fires,
    /// `elapsed` seconds into a pinch that `isPickedUp`, and `canStillHold`
    /// while it counts down toward its hold, as `press` tunes it: none until
    /// its pickup delay; then the pop, up to `pickedUpShare`, overshooting on
    /// the way; then, while it can still hold, rising, quickly at first, as a
    /// quadratic eases out, to all of it at its hold's duration, and no more
    /// after; and otherwise staying picked up. None for a pinch that hasn't
    /// picked up, or a time that isn't one.
    public static func progress(
        after elapsed: Double,
        isPickedUp: Bool,
        canStillHold: Bool,
        tunedAs press: SurfacePress.Tuning = SurfacePress.Tuning()
    ) -> Double {
        let lift = press.lift
        guard isPickedUp, elapsed.isFinite, elapsed > press.pickUpDelay else { return 0 }
        let sincePickUp = elapsed - press.pickUpDelay
        if sincePickUp < lift.popDuration {
            return lift.pickedUpShare * popCurve(sincePickUp / lift.popDuration, overshoot: lift.popOvershoot)
        }
        let rise = press.holdDuration - press.pickUpDelay - lift.popDuration
        guard canStillHold, rise > 0 else { return lift.pickedUpShare }
        let share = min((sincePickUp - lift.popDuration) / rise, 1)
        return lift.pickedUpShare + (1 - lift.pickedUpShare) * (1 - (1 - share) * (1 - share))
    }

    /// How far the lift of the pinch `press` has come, `elapsed` seconds into
    /// it, as its tuning says (`progress(after:isPickedUp:canStillHold:tunedAs:)`).
    public static func progress(after elapsed: Double, of press: SurfacePress) -> Double {
        progress(after: elapsed, isPickedUp: press.isPickedUp, canStillHold: press.canStillHold, tunedAs: press.tuning)
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

    /// How much larger it shows at `progress` of its lift: in proportion,
    /// from 1 at rest to `Tuning.fullScale`.
    public static func scale(at progress: Double, tunedAs lift: Tuning = Tuning()) -> Double {
        1 + (lift.fullScale - 1) * held(progress)
    }

    /// How far toward the viewer it stands at `progress` of its lift, in
    /// meters: in proportion, from none to `Tuning.fullDepth`.
    public static func depth(at progress: Double, tunedAs lift: Tuning = Tuning()) -> Double {
        lift.fullDepth * held(progress)
    }

    /// The pop's curve, from 0 as it begins to 1 as it's done, `share` of the
    /// way through it: an ease out that backs by `overshoot`, which at
    /// 1.70158 rises to about 1.1 a little past halfway, then settles, as a
    /// spring with a little bounce does; 0 before it, and 1 after.
    public static func popCurve(_ share: Double, overshoot: Double = Tuning().popOvershoot) -> Double {
        guard share > 0 else { return 0 }
        guard share < 1 else { return 1 }
        let s = share - 1
        return 1 + (overshoot + 1) * s * s * s + overshoot * s * s
    }

    /// `progress` held within 0...1, and none for one that isn't a number.
    private static func held(_ progress: Double) -> Double {
        progress.isNaN ? 0 : min(max(progress, 0), 1)
    }
}
