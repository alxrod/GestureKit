/// The numbers and choices a pluck goes by: how long and how still a pinch
/// on an item in a scrolling container is held before the item lifts, how
/// long after the lift its pull arms, which moves pull it out, what the
/// container's scroll does meanwhile, and, for the visionOS adapter, how its
/// gestures attach and how the lift and the pull look. Every rule reads them
/// from here, so the lab can change them live; a pinch keeps the tuning it
/// began with, so each pinch in a trace is judged by one tuning.
///
/// The defaults: a pinch its container scrolls with, or that moves 40 pt
/// before its hold, is the container's scroll; held still half a second,
/// the item lifts and the container's scroll stops under it; two tenths of
/// a second later its pull arms, and a move of 6 mm any way from where the
/// pinch stood then pulls it out. They're the numbers the pluck first
/// shipped with but four, which the lab's traces on the headset showed
/// almost never pulled and often lost the hold: the drag's first word, at
/// its 15 pt start, no longer makes the pinch a scroll (`holdStillness`); a
/// pull needs no depth (`pullsAnyDirection`), counts only the move since the
/// arming (`measuresPullFromArming`), and is under a third as far
/// (`pullDistance`); and a lifted item stays up as the hold's press ends
/// while the drag hasn't spoken, since stopping the container's scroll as
/// the item lifts may cancel the press (`pressEndSettlesLiftedItem`).
///
/// Distances on the item are in its own points, as a SwiftUI drag reports
/// them, with +z toward the viewer; the pull's distance is in meters, which
/// the caller converts by the points it measures to a meter, about 1,360 at
/// a window's own size.
public struct PluckTuning: Equatable, Sendable, Codable {
    /// How long a pinch is held, in seconds, before its item lifts: half a
    /// second. Longer keeps a scroll that begins with a pause from lifting
    /// the item it began on.
    public var holdDuration: Double

    /// How far a pinch may move from where it touched, in the item's points,
    /// and still be held: a move the drag reports before the hold, this far
    /// or farther, makes the pinch the container's scroll for good. 40 pt,
    /// about 3 cm at a window's own size.
    ///
    /// The container's scroll gives the hold up anyway, as its scroll view
    /// says it moves with the pinch or coasts (`PluckScrolls`), so this
    /// need only catch a big move the scroll view doesn't take, as a yank
    /// toward the viewer before the hold. On the headset a hand that has
    /// just pinched settles about 15 pt in its first quarter second, with
    /// the container still; 40 pt leaves well over twice that.
    ///
    /// The drag says nothing until the pinch has moved `dragStartDistance`,
    /// by its own measure, so a stillness no greater than that takes the
    /// drag's first word before the hold as a move, whatever it says, as
    /// the pluck first shipped, at 15 pt, which turned the settling of a
    /// fresh pinch into a scroll the container never made.
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

    /// How far an armed pinch moves to pull its item out, in meters: 6 mm,
    /// about 8 pt at a window's own size, any way from where the pinch stood
    /// as the pull armed, by default. The pull rule reads it in the item's
    /// points (`pullThreshold(pointsPerMeter:)`).
    ///
    /// On the headset the drag reports depth in steps of about 4 pt, so one
    /// step alone never pulls, and two do; a hand trying to hold still moved
    /// a point or two between the drag's words; and a hand meaning to pull
    /// moved 15 pt or more within a few tenths of a second of the lift. The
    /// pluck first shipped at 2 cm toward the viewer, from the touch, which,
    /// with depth that coarse, almost never pulled.
    public var pullDistance: Double

    /// How deep a pull must go for each unit it drifts across the
    /// container's plane, with `pullsAnyDirection` off: 0.5, 1 deep for
    /// every 2 across, as the pluck first shipped, so a move must leave the
    /// plane at about 27° or more. At 0, any move far enough toward the
    /// viewer pulls, however far it drifts across.
    public var pullDepthPerDrift: Double

    /// Whether any move as far as the pull's distance pulls, across or in
    /// depth, toward the viewer or away, the depth per drift aside: on by
    /// default. A lifted item's container no longer scrolls under it, so no
    /// move of its pinch can be a scroll, and the drag's depth comes through
    /// small and coarse while a hand coming out drifts across as far or
    /// farther. Off, a pull comes toward the viewer, at `pullDepthPerDrift`.
    public var pullsAnyDirection: Bool

    /// Whether an armed pinch's move is measured from where it stood as its
    /// pull armed, as by default, or from where it touched, as the pluck
    /// first shipped.
    ///
    /// From the arming, a hand that drifted during the hold, as hands do,
    /// doesn't pull the instant it arms. Where it stood is where the drag
    /// last said; should the drag not have spoken by then, the pinch stood
    /// within the drag's start of the touch, so the move is measured from
    /// the touch, and the drag's first word, the first sign of a move, pulls
    /// at the default distances, rather than asking for the pull's distance
    /// past the drag's start. From the touch, a hand already on its way out
    /// catches up as the pull arms.
    public var measuresPullFromArming: Bool

    /// Whether a drag's z grows toward the viewer, as SwiftUI's does, which
    /// the pull rule takes it to: off reads it the other way round, to try
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
    /// drag doesn't have the pinch. Off by default: the item stays lifted,
    /// so a press that ends as the lift stops the container's scroll, as it
    /// may, doesn't drop it and lose its pull. It settles then as the drag
    /// ends or is cancelled, as the item's tap comes on release, before or
    /// after the press's end, as the next pinch on it or anywhere else in
    /// the container begins, or as the item goes. On, as the pluck first
    /// shipped, the press's end is the pinch let go.
    public var pressEndSettlesLiftedItem: Bool

    /// How long, in seconds, after a pinch that lifted its item is over its
    /// item's tap is still taken as its release, which is no tap: a second.
    /// The tap comes as a pinch is let go, before or after its gestures
    /// end; this is only a backstop, since the first tap in it, and the
    /// next pinch's touch, end it.
    public var releaseTapGrace: Double

    /// For the adapter: whether the hold counts from the pull's drag rather
    /// than from the item's press. Off by default: the item is a button,
    /// whose press the hold counts from, and whose tap is the item's. On,
    /// the item has no button, its drag is its only gesture, the hold counts
    /// from the drag's first word, and a pinch the drag tells nothing of as
    /// it ends is the item's tap; lower the drag's start with it, to 0 pt,
    /// so the drag hears the touch.
    public var holdsFromTheDrag: Bool

    /// For the adapter: whether the pull's drag is attached beside the
    /// item's own gestures, as a simultaneous gesture, as by default; off,
    /// it's attached as an ordinary gesture, which the item's button takes
    /// precedence over.
    public var pullDragIsSimultaneous: Bool

    /// For the adapter: how far in front of the drag's location what an item
    /// pulls out stands, in the item's points, so it comes out in front of
    /// the window rather than inside it: 100 pt.
    public var pushTowardViewer: Double

    /// For the adapter: how much larger a lifted item shows: 8%.
    public var liftScale: Double

    /// For the adapter: how far toward the viewer a lifted item stands, in
    /// its points: 36 pt, about 2.6 cm at a window's own size.
    public var liftDepth: Double

    /// A tuning with GestureKit's defaults, changed as given.
    public init(
        holdDuration: Double = 0.5,
        holdStillness: Double = 40,
        pullArmDelay: Double = 0.2,
        dragStartDistance: Double = 15,
        pullDistance: Double = 0.006,
        pullDepthPerDrift: Double = 0.5,
        pullsAnyDirection: Bool = true,
        measuresPullFromArming: Bool = true,
        depthGrowsTowardViewer: Bool = true,
        depthScale: Double = 1,
        stopsScrollUnderLiftedItem: Bool = true,
        scrollSettlesLiftedItem: Bool = true,
        pressEndSettlesLiftedItem: Bool = false,
        releaseTapGrace: Double = 1,
        holdsFromTheDrag: Bool = false,
        pullDragIsSimultaneous: Bool = true,
        pushTowardViewer: Double = 100,
        liftScale: Double = 1.08,
        liftDepth: Double = 36
    ) {
        self.holdDuration = holdDuration
        self.holdStillness = holdStillness
        self.pullArmDelay = pullArmDelay
        self.dragStartDistance = dragStartDistance
        self.pullDistance = pullDistance
        self.pullDepthPerDrift = pullDepthPerDrift
        self.pullsAnyDirection = pullsAnyDirection
        self.measuresPullFromArming = measuresPullFromArming
        self.depthGrowsTowardViewer = depthGrowsTowardViewer
        self.depthScale = depthScale
        self.stopsScrollUnderLiftedItem = stopsScrollUnderLiftedItem
        self.scrollSettlesLiftedItem = scrollSettlesLiftedItem
        self.pressEndSettlesLiftedItem = pressEndSettlesLiftedItem
        self.releaseTapGrace = releaseTapGrace
        self.holdsFromTheDrag = holdsFromTheDrag
        self.pullDragIsSimultaneous = pullDragIsSimultaneous
        self.pushTowardViewer = pushTowardViewer
        self.liftScale = liftScale
        self.liftDepth = liftDepth
    }

    /// Which moves of an armed pinch pull its item out: any way, as by
    /// default; else toward the viewer, at `pullDepthPerDrift` deep for each
    /// unit across, however far across at 0.
    public var pullRule: PluckPullRule {
        if pullsAnyDirection { return .anyDirection }
        return pullDepthPerDrift > 0 ? .outOfThePlane(depthPerDrift: pullDepthPerDrift) : .towardTheViewer
    }

    /// Where an armed pinch's move is measured from: where it stood as its
    /// pull armed, as by default, or where it touched.
    public var pullOrigin: PluckPullOrigin {
        measuresPullFromArming ? .arming : .touch
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
    /// caller measures a meter where the item is: 6 mm is about 8 pt at a
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

    /// Judges whether an armed pinch at `translation` from where it touched,
    /// in the item's points, pulls its item out, by the pull rule, at
    /// `pointsPerMeter`: its move from `armedAt`, where the drag said it
    /// stood as its pull armed, should the tuning measure from there; else,
    /// or with the drag silent then, nil, its move from the touch.
    public func judgePull(_ translation: SIMD3<Double>, armedAt: SIMD3<Double>?, pointsPerMeter: Double) -> PluckPullJudgement {
        let threshold = pullThreshold(pointsPerMeter: pointsPerMeter)
        guard measuresPullFromArming, let armedAt else {
            return pullRule.judge(viewerTranslation(translation), threshold: threshold, from: .touch)
        }
        return pullRule.judge(viewerTranslation(translation - armedAt), threshold: threshold, from: .arming)
    }
}

extension PluckTuning: Tunable {
    public static var defaults: PluckTuning { PluckTuning() }

    public static let parameters: [TuningParameter<PluckTuning>] = [
        .number(\.holdDuration, key: "holdDuration", title: "Hold", unit: "s", range: 0.1...2, step: 0.05),
        .number(\.holdStillness, key: "holdStillness", title: "Hold stillness", unit: "pt", range: 0...100, step: 1),
        .number(\.pullArmDelay, key: "pullArmDelay", title: "Pull arms after the lift", unit: "s", range: 0...1, step: 0.05),
        .number(\.dragStartDistance, key: "dragStartDistance", title: "Drag start", unit: "pt", range: 0...60, step: 1),
        .number(\.pullDistance, key: "pullDistance", title: "Pull distance", unit: "m", range: 0.002...0.1, step: 0.001),
        .number(\.pullDepthPerDrift, key: "pullDepthPerDrift", title: "Pull depth per drift across", range: 0...3, step: 0.05),
        .toggle(\.pullsAnyDirection, key: "pullsAnyDirection", title: "Any direction pulls"),
        .toggle(\.measuresPullFromArming, key: "measuresPullFromArming", title: "Pull measured from where it armed"),
        .toggle(\.depthGrowsTowardViewer, key: "depthGrowsTowardViewer", title: "Drag's z grows toward you"),
        .number(\.depthScale, key: "depthScale", title: "Drag's depth scale", range: 0.25...4, step: 0.05),
        .toggle(\.stopsScrollUnderLiftedItem, key: "stopsScrollUnderLiftedItem", title: "Scroll stops under a lifted item"),
        .toggle(\.scrollSettlesLiftedItem, key: "scrollSettlesLiftedItem", title: "A scroll settles a lifted item"),
        .toggle(\.pressEndSettlesLiftedItem, key: "pressEndSettlesLiftedItem", title: "The press's end settles a lifted item"),
        .number(\.releaseTapGrace, key: "releaseTapGrace", title: "Release tap grace", unit: "s", range: 0...3, step: 0.1),
        .toggle(\.holdsFromTheDrag, key: "holdsFromTheDrag", title: "Hold counts from the drag, not a button"),
        .toggle(\.pullDragIsSimultaneous, key: "pullDragIsSimultaneous", title: "Pull drag is simultaneous"),
        .number(\.pushTowardViewer, key: "pushTowardViewer", title: "Pulled thing's push toward you", unit: "pt", range: 0...300, step: 5),
        .number(\.liftScale, key: "liftScale", title: "Lift scale", range: 1...1.3, step: 0.01),
        .number(\.liftDepth, key: "liftDepth", title: "Lift depth", unit: "pt", range: 0...120, step: 2),
    ]
}
