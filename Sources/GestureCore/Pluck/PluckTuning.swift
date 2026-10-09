/// The numbers and choices a pluck goes by: how long and how still a pinch
/// on an item in a scrolling container is held before the item lifts, how
/// long after the lift its pull arms, which moves pull it out, and what the
/// container's scroll does meanwhile. Every rule reads them from here, so
/// the lab can change them live; a pinch keeps the tuning it began with, so
/// each pinch in a trace is judged by one tuning.
///
/// The defaults are the ones the pluck shipped with: a pinch that moves
/// first is the container's scroll; held still half a second, the item
/// lifts and the container's scroll stops under it; two tenths of a second
/// later, a move of 2 cm toward the viewer, 1 deep for every 2 across,
/// pulls it out.
///
/// Distances on the item are in its own points, as a SwiftUI drag reports
/// them, with +z toward the viewer; the pull's distance is in meters, which
/// the caller converts by the points it measures to a meter.
public struct PluckTuning: Equatable, Sendable, Codable {
    /// How long a pinch is held, in seconds, before its item lifts: half a
    /// second. Longer keeps a scroll that begins with a pause from lifting
    /// the item it began on.
    public var holdDuration: Double

    /// How far a pinch may move from where it touched, in the item's points,
    /// and still be held: a move the drag reports before the hold, this far
    /// or farther, makes the pinch the container's scroll for good.
    ///
    /// The drag says nothing until the pinch has moved `dragStartDistance`,
    /// by its own measure, so a stillness no greater than that is the drag
    /// start's: the drag's first word before the hold is a move, whatever
    /// it says. That's the default, 15 pt, equal to the drag's start. A
    /// stricter stillness takes a drag that starts sooner; a looser one lets
    /// the drag's first words go by.
    public var holdStillness: Double

    /// How long after its item lifts a pinch's pull arms, in seconds: two
    /// tenths, so the lift shows before anything can come out. Between the
    /// lift and the arming, a move neither pulls nor scrolls.
    public var pullArmDelay: Double

    /// How far a pinch moves from where it touched, in the item's points,
    /// before the pull's drag says anything: its drag gesture's minimum
    /// distance. 15 pt, about 1.1 cm at a window's own size. A drag that
    /// starts at 0 pt hears every pinch, its end and all, but may compete
    /// with the container's scroll for it.
    public var dragStartDistance: Double

    /// How far toward the viewer, in meters, an armed pinch moves from where
    /// it touched to pull its item out: 2 cm. The pull rule reads it in the
    /// item's points (`pullThreshold(pointsPerMeter:)`).
    public var pullDistance: Double

    /// Which moves of an armed pinch pull its item out: by default out of
    /// the container's plane, 1 deep for every 2 across.
    public var pullRule: PluckPullRule

    /// Whether a drag's z grows toward the viewer, as SwiftUI's does, which
    /// the pull rule takes it to: false reads it the other way round, to try
    /// whether the drag the pull hears runs its depth away from the viewer.
    public var depthGrowsTowardViewer: Bool

    /// What the drag's depth is multiplied by before the pull rule reads it,
    /// against its moves across, which it leaves alone: 1, the same points.
    /// To try whether the drag reports its depth at another scale than its
    /// moves across.
    public var depthScale: Double

    /// Whether the container's scroll stops while one of its items is
    /// lifted, so the lifted pinch's moves belong to the item: on by
    /// default. Off, the container goes on scrolling under a lifted item,
    /// and only a move toward the viewer, which a scroll ignores, pulls it.
    public var stopsScrollUnderLiftedItem: Bool

    /// Whether the container beginning to scroll settles a lifted item: on
    /// by default, so an item lifted as its container began to scroll, by
    /// another hand or a scroll under way, goes back down.
    public var scrollSettlesLiftedItem: Bool

    /// Whether a lifted item settles as the hold's press ends while the
    /// drag doesn't have the pinch: on by default, the press's end being
    /// the pinch let go. Off, the item stays lifted, so a press that ends
    /// as the lift stops the container's scroll, as it might, doesn't drop
    /// it; it settles then as the drag ends or is cancelled, the next pinch
    /// begins, or the item goes. Nothing may tell that the pinch was let go
    /// should the drag never speak, so it's best tried with a drag that
    /// starts at 0 pt.
    public var pressEndSettlesLiftedItem: Bool

    /// How long, in seconds, after a pinch that lifted its item is over its
    /// item's tap is still taken as its release, which is no tap: a second.
    /// The tap comes as a pinch is let go, before or after its gestures
    /// end; this is only a backstop, since the first tap in it, and the
    /// next pinch's touch, end it.
    public var releaseTapGrace: Double

    /// A tuning with the defaults the pluck shipped with, changed as given.
    public init(
        holdDuration: Double = 0.5,
        holdStillness: Double = 15,
        pullArmDelay: Double = 0.2,
        dragStartDistance: Double = 15,
        pullDistance: Double = 0.02,
        pullRule: PluckPullRule = .outOfThePlane(depthPerDrift: 0.5),
        depthGrowsTowardViewer: Bool = true,
        depthScale: Double = 1,
        stopsScrollUnderLiftedItem: Bool = true,
        scrollSettlesLiftedItem: Bool = true,
        pressEndSettlesLiftedItem: Bool = true,
        releaseTapGrace: Double = 1
    ) {
        self.holdDuration = holdDuration
        self.holdStillness = holdStillness
        self.pullArmDelay = pullArmDelay
        self.dragStartDistance = dragStartDistance
        self.pullDistance = pullDistance
        self.pullRule = pullRule
        self.depthGrowsTowardViewer = depthGrowsTowardViewer
        self.depthScale = depthScale
        self.stopsScrollUnderLiftedItem = stopsScrollUnderLiftedItem
        self.scrollSettlesLiftedItem = scrollSettlesLiftedItem
        self.pressEndSettlesLiftedItem = pressEndSettlesLiftedItem
        self.releaseTapGrace = releaseTapGrace
    }

    /// How long a pinch is held before its item lifts.
    public var holdTime: Duration {
        .seconds(holdDuration)
    }

    /// How long after the lift the pull arms.
    public var pullArmTime: Duration {
        .seconds(pullArmDelay)
    }

    /// How long a lifting pinch's release tap is waited for.
    public var releaseTapTime: Duration {
        .seconds(releaseTapGrace)
    }

    /// The pull's distance in the item's points, at `pointsPerMeter`, as the
    /// caller measures a meter where the item is: 2 cm is about 27 pt at a
    /// window's own size.
    public func pullThreshold(pointsPerMeter: Double) -> Double {
        pullDistance * pointsPerMeter
    }

    /// Whether a move the drag reports `distance` from where the pinch
    /// touched, in the item's points, breaks the hold's stillness: always,
    /// with a stillness no greater than the drag's start, since the drag has
    /// moved that far to speak at all; else once it reaches the stillness.
    public func breaksStillness(_ distance: Double) -> Bool {
        holdStillness <= dragStartDistance || distance >= holdStillness
    }

    /// The drag's `translation` as the pull rule reads it: its depth turned
    /// toward the viewer, should the tuning say it runs away, and scaled by
    /// `depthScale`; its moves across as they are.
    public func viewerTranslation(_ translation: SIMD3<Double>) -> SIMD3<Double> {
        let depth = depthGrowsTowardViewer ? translation.z : -translation.z
        return SIMD3(translation.x, translation.y, depth * depthScale)
    }

    /// Judges whether an armed pinch's move, `translation` from where it
    /// touched, in the item's points, pulls its item out, by the pull rule,
    /// at `pointsPerMeter`.
    public func judgePull(_ translation: SIMD3<Double>, pointsPerMeter: Double) -> PluckPullJudgement {
        pullRule.judge(viewerTranslation(translation), threshold: pullThreshold(pointsPerMeter: pointsPerMeter))
    }
}
