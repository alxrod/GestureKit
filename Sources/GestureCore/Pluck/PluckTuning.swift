/// The numbers and choices a pluck goes by: how long and how still a pinch
/// on an item in a scrolling container is held before the item lifts, how
/// the lifted item follows the hand until it breaks free, how far the hand
/// goes before it does, how long after the lift it may, what the
/// container's scroll does meanwhile, and, for the visionOS adapter, how its
/// gestures attach, how the lift looks, and where what breaks free spawns.
/// Every rule reads them from here, so the lab can change them live; a pinch
/// keeps the tuning it began with, so each pinch in a trace is judged by one
/// tuning.
///
/// The defaults: a pinch is the container's scroll unless it's a hold. One
/// its container's scroll view scrolls with, or whose scroll offset moves
/// a point from where it stood at the touch, or that moves 10 pt along the
/// scroll, or 40 pt any way, before its hold, is the container's scroll,
/// for good; held a quarter second with none of those, the item lifts and
/// the container's scroll stops under it; lifted, it
/// stays in its container, following the hand a little, half of its move at
/// first and less as it goes on, toward 20 pt, so it feels held, unless the
/// hand moves mostly along the scroll, which gives the pinch back to it; and
/// once the hand has gone 2.5 cm any other way from where it stood as the
/// item lifted, and two tenths of a second have passed since the lift, the
/// item breaks free and spawns into the room at the hand, where the pluck's
/// part ends and a carry's begins (`PluckHandoff`).
///
/// Alex asked for the quarter second and the sticky lift on October 9, after
/// trying the lab: the half-second hold felt too long, and at the 6 mm pull
/// it had then, the item spawned the instant it lifted. That tuning, and the
/// one the pluck first shipped with, are each a few values away: a hold of
/// 0.5 s, a break-free distance of 6 mm, and a follow share of 0; and, as
/// first shipped, 2 cm toward the viewer from the touch, at a stillness of
/// 15 pt, with the press's end settling a lift. The hold watched only the
/// scroll view's phase and a move of 40 pt any way until Alex found, after
/// the quarter second, that pinches meant to scroll still lifted their item
/// and lost the scroll; that's three values away: an along-scroll stillness
/// of 40 pt, the scroll offset unwatched, and no lift given back.
///
/// Distances on the item are in its own points, as a SwiftUI drag reports
/// them, with +z toward the viewer; the break-free distance is in meters of
/// the hand's move, which the caller converts by the points it measures to
/// a meter of it, about 1,360 at a window's own size.
public struct PluckTuning: Equatable, Sendable, Codable {
    /// How long a pinch is held, in seconds, before its item lifts: a
    /// quarter second, half the half second the pluck first shipped with, as
    /// Alex asked on October 9, the half second having felt too long.
    ///
    /// The pull's arming counts from the lift, so it comes as much sooner,
    /// 0.45 s after the touch rather than 0.7 s. The container's scroll, its
    /// offset, and the hold's stillness give the hold up as before, but have
    /// half as long to: a pinch that moves less than the drag's 15 pt start
    /// in its first quarter second, then scrolls, lifts the item it began
    /// on, which holds the scroll off, until its move along the scroll gives
    /// the pinch back to it (`givesLiftBackToScroll`). Longer keeps such a
    /// scroll from lifting anything; so may a drag that starts sooner
    /// (`dragStartDistance`), which hears a smaller move along the scroll.
    public var holdDuration: Double

    /// How far a pinch may move from where it touched, any way, in the
    /// item's points, and still be held: a move the drag reports before the
    /// hold, this far or farther, makes the pinch the container's scroll for
    /// good. 40 pt, about 3 cm at a window's own size. It's the allowance
    /// across the scroll and in depth; along the scroll, the hold watches
    /// far more closely (`holdStillnessAlongScroll`).
    ///
    /// The container's scroll gives the hold up anyway, as its scroll view
    /// says it moves with the pinch or coasts, or its offset moves
    /// (`PluckScrolls`, `scrollOffsetStillness`), so this need only catch a
    /// big move the scroll view doesn't take, as a yank toward the viewer
    /// before the hold. On the headset a hand that has just pinched settles
    /// about 15 pt in its first quarter second, with the container still;
    /// 40 pt leaves well over twice that.
    ///
    /// The drag says nothing until the pinch has moved `dragStartDistance`,
    /// by its own measure, so a stillness no greater than that takes the
    /// drag's first word before the hold as a move, whatever it says, as
    /// the pluck first shipped, at 15 pt, which turned the settling of a
    /// fresh pinch into a scroll the container never made.
    public var holdStillness: Double

    /// How far a pinch may move along its container's scroll, in the item's
    /// points, and still be held: 10 pt, about 7 mm at a window's own size,
    /// a move the drag reports before the hold this far along the scroll
    /// making the pinch the container's scroll for good. A move along the
    /// scroll is what a scroll is, so this is about where a scroll view's
    /// own pan begins, rather than the 40 pt the hold allows any way, which
    /// let a slow scroll's first 40 pt go by before its scroll view said it
    /// scrolled, its item lifting and the scroll lost under it, as Alex found
    /// on October 9. The one fresh pinch's settling the headset traced went
    /// 8.2 pt along the scroll and 12.5 across (item 2), which this lets by.
    ///
    /// The drag says nothing before its 15 pt start, so a pinch whose first
    /// word lies two thirds along the scroll is a scroll as it speaks. At
    /// `holdStillness` or more it changes nothing, the hold watching moves
    /// along the scroll as it watches any other, as it did until October 9.
    public var holdStillnessAlongScroll: Double

    /// Whether the hold watches its container's scroll offset as well as its
    /// scroll view's phase: on by default, so any move of the container's
    /// content past `scrollOffsetStillness` from where it stood at the
    /// touch, before the hold, makes the pinch the container's scroll for
    /// good, whatever phase the scroll view says it's in. The phase may come
    /// later than the content moves, and sits in tracking from the touch,
    /// moving or not, so it isn't counted as scrolling: Vignette's grid logs
    /// a still pinch going from idle to tracking, 0 pt down.
    public var holdWatchesScrollOffset: Bool

    /// How far the container's scroll offset may move from where it stood
    /// at a pinch's touch, before the hold, in points, and the item still
    /// lift: 1 pt. Content at rest doesn't move, and a scroll moves it some
    /// points a frame; a point leaves room for a layout's rounding.
    public var scrollOffsetStillness: Double

    /// How long after its item lifts a pinch's pull arms, in seconds: two
    /// tenths, the least time the item shows lifted before it may break
    /// free. Between the lift and the arming, a move neither breaks it free
    /// nor scrolls, though the item follows it, and the move counts from the
    /// lift, so a hand already past the break-free distance breaks it free
    /// at its first word after the arming.
    ///
    /// With the break-free distance doing the work of keeping the item in
    /// its container, this is a floor rather than the guard it was at 6 mm:
    /// about a person's reaction time and most of the lift's 0.32 s spring,
    /// so even a hand already moving as the item lifts sees it lift and hold
    /// before it comes free. A hand pulling on purpose takes about that long
    /// to go 2.5 cm, so it seldom waits for it. 0 arms at the lift.
    public var pullArmDelay: Double

    /// How far a pinch moves from where it touched, in the item's points,
    /// before the pull's drag says anything: its drag gesture's minimum
    /// distance. 15 pt, about 1.1 cm at a window's own size. A drag that
    /// starts at 0 pt hears every pinch, its end and all, but may compete
    /// with the container's scroll for it.
    public var dragStartDistance: Double

    /// How far a lifted pinch moves before its item breaks free and spawns
    /// into the room, in meters of the hand's move: 2.5 cm, 34 pt at a
    /// window's own size, any way from where the pinch stood as its item
    /// lifted, by default (`pullRule`, `pullOrigin`). Until then the item
    /// stays lifted in its container, following the hand on its tether
    /// (`followShare`, `followCap`), so the lifted state feels sticky. The
    /// pull rule reads it in the item's points
    /// (`breakFreeThreshold(pointsPerMeter:)`), which the adapter measures
    /// for a meter of the hand.
    ///
    /// It replaces the 6 mm pull of October 9's lab, which a hand passed in
    /// a blink, so the item spawned the instant it lifted. 2.5 cm is over
    /// twice the 15 pt, 1.1 cm, a fresh pinch settles, and a hand trying to
    /// hold still moved a point or two between the drag's words, so a still
    /// hand never breaks free; and a hand meaning to pull, which moved 15 pt
    /// within a few tenths of a second of the lift on the headset, covers it
    /// in about a third of a second, long enough to feel the item hold. The
    /// drag reports depth in steps of about 4 pt, so a pull straight out
    /// takes eight or nine of them. The pluck first shipped at 2 cm toward
    /// the viewer, from the touch, which, with depth that coarse, almost
    /// never pulled.
    public var breakFreeDistance: Double

    /// How much of the hand's move a lifted item follows at first, short of
    /// breaking free: half. Its follow eases toward `followCap` as the hand
    /// goes on (`PluckTether`), as a scroll view's content follows a pinch
    /// past its end, so the item feels held to its place, and the farther
    /// the hand goes, the harder it pulls. 0 follows nothing, as the pluck
    /// did until October 9.
    public var followShare: Double

    /// How far a lifted item follows at most, in its points: 20 pt, about
    /// 1.5 cm at a window's own size, which its follow eases toward and never
    /// reaches. At the default break-free distance it has followed 9 pt, a
    /// quarter of the hand's 34 pt, as it breaks free, the hand's last
    /// centimeter moving it hardly at all, which is the tension a rubber band
    /// has just before it lets go. 0 follows nothing.
    public var followCap: Double

    /// How deep a pull must go to break free for each unit it drifts across
    /// the container's plane, with `pullsAnyDirection` off: 0.5, 1 deep for
    /// every 2 across, as the pluck first shipped, so a move must leave the
    /// plane at about 27° or more. At 0, any move far enough toward the
    /// viewer pulls, however far it drifts across.
    public var pullDepthPerDrift: Double

    /// Whether any move as far as the break-free distance pulls, across or in
    /// depth, toward the viewer or away, the depth per drift aside: on by
    /// default. A lifted item's container no longer scrolls under it, so no
    /// move of its pinch can be a scroll, and the drag's depth comes through
    /// small and coarse while a hand coming out drifts across as far or
    /// farther. Off, a pull comes toward the viewer, at `pullDepthPerDrift`.
    public var pullsAnyDirection: Bool

    /// Whether an armed pinch's move is measured from where it stood as its
    /// item lifted: on by default, and ahead of `measuresPullFromArming`.
    ///
    /// A hand that drifted during the hold, as hands do, doesn't pull the
    /// instant it arms, and a hand that comes out as soon as the item lifts,
    /// as the headset's traces showed one 13 pt toward the viewer in the two
    /// tenths of a second before the arming, has that move counted, so it
    /// catches up as the pull arms. Where it stood is where the drag last
    /// said; should the drag not have spoken by then, the pinch stood within
    /// the drag's start of the touch, so the move is measured from the
    /// touch, rather than asking for the break-free distance past the drag's
    /// start. The lifted item's follow is measured from the same place.
    public var measuresPullFromLift: Bool

    /// Whether an armed pinch's move is measured from where it stood as its
    /// pull armed, should `measuresPullFromLift` be off: off by default. On,
    /// only a move since the arming counts, a hand's move between the lift
    /// and the arming lost; with both off, the move is measured from the
    /// touch, as the pluck first shipped, so a hand already on its way out
    /// catches up as the pull arms, and one that drifted during the hold may
    /// pull the instant it arms.
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

    /// Whether a lifted item held short of breaking free gives its pinch
    /// back to the container's scroll as the hand moves mostly along it: on
    /// by default, as "Scrolling always needs to take precedent over pluck",
    /// Alex said on October 9. A move from where the item lifted at least
    /// `holdStillnessAlongScroll` along the scroll, and twice as far along
    /// it as across it and in depth, settles the item, which turns the
    /// container's scroll on again, and makes the pinch a scroll for the
    /// rest of it, so a scroll begun after a pause as long as the hold
    /// doesn't pull a card out instead. So an item can't be pulled out
    /// mostly along the scroll: up or down out of a grid that scrolls
    /// vertically; across, toward the viewer, or away, it can.
    ///
    /// Whether the scroll view takes up the pinch already under way, its
    /// scroll having been off as it began, only the headset can tell: if it
    /// doesn't, the pinch does nothing until it's let go, the next pinch
    /// scrolling. Off, a held item keeps every move, as until October 9.
    public var givesLiftBackToScroll: Bool

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
    /// pulls out spawns, in the item's points, so it comes out in front of
    /// the window rather than inside it: 100 pt. The carry of what spawned
    /// keeps that offset from the hand, as it carries its middle 1:1 from
    /// where it spawned.
    public var pushTowardViewer: Double

    /// For the adapter: how much larger a lifted item shows: 8%.
    public var liftScale: Double

    /// For the adapter: how far toward the viewer a lifted item stands, in
    /// its points: 36 pt, about 2.6 cm at a window's own size.
    public var liftDepth: Double

    /// A tuning with GestureKit's defaults, changed as given.
    public init(
        holdDuration: Double = 0.25,
        holdStillness: Double = 40,
        holdStillnessAlongScroll: Double = 10,
        holdWatchesScrollOffset: Bool = true,
        scrollOffsetStillness: Double = 1,
        pullArmDelay: Double = 0.2,
        dragStartDistance: Double = 15,
        breakFreeDistance: Double = 0.025,
        followShare: Double = 0.5,
        followCap: Double = 20,
        pullDepthPerDrift: Double = 0.5,
        pullsAnyDirection: Bool = true,
        measuresPullFromLift: Bool = true,
        measuresPullFromArming: Bool = false,
        depthGrowsTowardViewer: Bool = true,
        depthScale: Double = 1,
        stopsScrollUnderLiftedItem: Bool = true,
        givesLiftBackToScroll: Bool = true,
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
        self.holdStillnessAlongScroll = holdStillnessAlongScroll
        self.holdWatchesScrollOffset = holdWatchesScrollOffset
        self.scrollOffsetStillness = scrollOffsetStillness
        self.pullArmDelay = pullArmDelay
        self.dragStartDistance = dragStartDistance
        self.breakFreeDistance = breakFreeDistance
        self.followShare = followShare
        self.followCap = followCap
        self.pullDepthPerDrift = pullDepthPerDrift
        self.pullsAnyDirection = pullsAnyDirection
        self.measuresPullFromLift = measuresPullFromLift
        self.measuresPullFromArming = measuresPullFromArming
        self.depthGrowsTowardViewer = depthGrowsTowardViewer
        self.depthScale = depthScale
        self.stopsScrollUnderLiftedItem = stopsScrollUnderLiftedItem
        self.givesLiftBackToScroll = givesLiftBackToScroll
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
    /// item lifted, as by default; else where it stood as its pull armed,
    /// should the tuning say so; else where it touched.
    public var pullOrigin: PluckPullOrigin {
        if measuresPullFromLift { return .lift }
        return measuresPullFromArming ? .arming : .touch
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

    /// The break-free distance in the item's points, at `pointsPerMeter`, as
    /// the caller measures a meter of the hand's move where the item is:
    /// 2.5 cm is 34 pt at a window's own size.
    public func breakFreeThreshold(pointsPerMeter: Double) -> Double {
        breakFreeDistance * pointsPerMeter
    }

    /// How a lifted item follows its pinch until it breaks free: a share of
    /// the hand's move, easing toward a cap.
    public var tether: PluckTether {
        PluckTether(share: followShare, cap: followCap)
    }

    /// Whether a move the drag reports `distance` from where the pinch
    /// touched, in the item's points, breaks the hold's stillness: always,
    /// with a stillness no greater than the drag's start, since the drag has
    /// moved that far to speak at all; else once it reaches the stillness.
    public func breaksStillness(_ distance: Double) -> Bool {
        holdStillness <= dragStartDistance || distance >= holdStillness
    }

    /// Whether a move the drag reports `distance` along the container's
    /// scroll from where the pinch touched, in the item's points, breaks the
    /// hold's stillness along it: once it reaches `holdStillnessAlongScroll`.
    public func breaksStillnessAlongScroll(_ distance: Double) -> Bool {
        distance.isFinite && distance >= holdStillnessAlongScroll
    }

    /// Whether the container's scroll offset, `distance` points from where
    /// it stood at the pinch's touch, gives the hold up: with the offset
    /// watched, once it's past `scrollOffsetStillness`.
    public func scrollOffsetGivesUpHold(_ distance: Double) -> Bool {
        holdWatchesScrollOffset && distance.isFinite && distance > scrollOffsetStillness
    }

    /// Whether a lifted pinch's `move` from where its item lifted, in the
    /// item's points, gives it back to the container's scroll along `axes`:
    /// with the tuning giving it back, at least `holdStillnessAlongScroll`
    /// along the scroll, and twice as far along it as across it and in
    /// depth.
    public func givesBackToScroll(_ move: SIMD3<Double>, along axes: PluckScrollAxes) -> Bool {
        guard givesLiftBackToScroll else { return false }
        let along = axes.distance(along: move)
        return along >= holdStillnessAlongScroll && along >= 2 * axes.distance(across: move)
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
    /// `pointsPerMeter`: its move from where the drag said it stood as its
    /// item lifted, `liftPoint`, or as its pull armed, `armingPoint`, as the
    /// tuning measures it (`pullOrigin`); else, or with the drag silent
    /// then, nil, its move from the touch.
    public func judgePull(
        _ translation: SIMD3<Double>,
        liftPoint: SIMD3<Double>?,
        armingPoint: SIMD3<Double>?,
        pointsPerMeter: Double
    ) -> PluckPullJudgement {
        let threshold = breakFreeThreshold(pointsPerMeter: pointsPerMeter)
        let origin = pullOrigin
        let point: SIMD3<Double>? = switch origin {
        case .touch: nil
        case .lift: liftPoint
        case .arming: armingPoint
        }
        guard let point else {
            return pullRule.judge(viewerTranslation(translation), threshold: threshold, from: .touch)
        }
        return pullRule.judge(viewerTranslation(translation - point), threshold: threshold, from: origin)
    }
}

extension PluckTuning: Tunable {
    public static var defaults: PluckTuning { PluckTuning() }

    public static let parameters: [TuningParameter<PluckTuning>] = [
        .number(\.holdDuration, key: "holdDuration", title: "Hold before the lift", unit: "s", range: 0.1...2, step: 0.05),
        .number(\.holdStillness, key: "holdStillness", title: "Hold stillness, any way", unit: "pt", range: 0...100, step: 1),
        .number(\.holdStillnessAlongScroll, key: "holdStillnessAlongScroll", title: "Hold stillness along the scroll", unit: "pt", range: 0...100, step: 1),
        .toggle(\.holdWatchesScrollOffset, key: "holdWatchesScrollOffset", title: "Hold watches the scroll offset"),
        .number(\.scrollOffsetStillness, key: "scrollOffsetStillness", title: "Scroll offset may move", unit: "pt", range: 0...20, step: 0.5),
        .number(\.pullArmDelay, key: "pullArmDelay", title: "Pull arms after the lift", unit: "s", range: 0...1, step: 0.05),
        .number(\.dragStartDistance, key: "dragStartDistance", title: "Drag start", unit: "pt", range: 0...60, step: 1),
        .number(\.breakFreeDistance, key: "breakFreeDistance", title: "Break free after", unit: "m", range: 0.002...0.1, step: 0.001),
        .number(\.followShare, key: "followShare", title: "Lifted item follows, at first", range: 0...1, step: 0.05),
        .number(\.followCap, key: "followCap", title: "Lifted item follows at most", unit: "pt", range: 0...60, step: 1),
        .number(\.pullDepthPerDrift, key: "pullDepthPerDrift", title: "Pull depth per drift across", range: 0...3, step: 0.05),
        .toggle(\.pullsAnyDirection, key: "pullsAnyDirection", title: "Any direction pulls"),
        .toggle(\.measuresPullFromLift, key: "measuresPullFromLift", title: "Pull measured from where it lifted"),
        .toggle(\.measuresPullFromArming, key: "measuresPullFromArming", title: "Else from where it armed, not the touch"),
        .toggle(\.depthGrowsTowardViewer, key: "depthGrowsTowardViewer", title: "Drag's z grows toward you"),
        .number(\.depthScale, key: "depthScale", title: "Drag's depth scale", range: 0.25...4, step: 0.05),
        .toggle(\.stopsScrollUnderLiftedItem, key: "stopsScrollUnderLiftedItem", title: "Scroll stops under a lifted item"),
        .toggle(\.givesLiftBackToScroll, key: "givesLiftBackToScroll", title: "A held item gives a move along the scroll back to it"),
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
