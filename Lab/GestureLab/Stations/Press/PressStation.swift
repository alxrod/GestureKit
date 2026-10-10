import GestureKit
import SwiftUI

/// The press station: a long surface in the space, one press taking every
/// pinch on it (`.surfacePress`), and a small tab beside its right end whose
/// own drag resizes the surface and whose hold is watched beside it
/// (`.holdWatch`).
///
/// - A tap drops a marker where it touched.
/// - A drag along moves the playhead: by the hand's moves, and let go on
///   the move it coasts on, slowing, until a pinch catches it; or, with
///   "A drag along scrolls" off, to where the pinch is on the surface, as a
///   scrub, which never coasts.
/// - A drag across does nothing.
/// - Held still, the pinch picks the surface up, which pops toward the
///   viewer; moved 2 cm then, it carries the surface with the hand, 3 cm
///   nearer, and let go it stays there.
/// - Held a full second, it holds, and "Held" flashes.
/// - A two-handed pinch on it stretches it, the press giving way.
///
/// Its press, lift, coast, and hold watch each have a tuning panel, and every
/// pinch, and every coast, is traced.
@MainActor @Observable
final class PressStation: LabStation {
    let id = "press"
    let title = "Press"
    let summary = "A surface to tap, drag, flick, pick up and carry, or hold; and a tab watched for a hold."
    let press = TuningStore<SurfacePress.Tuning>(namespace: "GestureLab.press")
    let lift = TuningStore<HoldLift.Tuning>(namespace: "GestureLab.press.lift")
    let coast = TuningStore<Coast.Tuning>(namespace: "GestureLab.press.coast")
    let holdWatch = TuningStore<HoldWatch.Tuning>(namespace: "GestureLab.press.hold-watch")
    let trace = TraceRecorder(logsSummariesPublicly: true)

    // MARK: Choices

    /// Whether a drag along scrolls the playhead by the hand's moves, and
    /// coasts, or moves it to where the pinch is, as a scrub.
    var dragAlongScrolls = true
    /// Whether every pickup is refused, to try a pinch that can't pick up
    /// going on as one that never could.
    var refusesPickUps = false
    /// Whether every carry is refused as it begins, to try the rest of the
    /// pinch doing nothing.
    var refusesCarries = false

    // MARK: The surface

    /// The surface's length, in meters.
    private(set) var length = 1.0
    /// Where the surface's middle stands in the space.
    private(set) var center = LabSpace.front
    /// Where the playhead is, in meters from the surface's left end.
    private(set) var playhead = 0.3
    /// Where taps dropped markers, in meters from the left end, the newest
    /// last.
    private(set) var markers: [Double] = []
    /// What flashes over the surface, and a count so each flash is its own.
    private(set) var flash: (text: String, serial: Int)?
    /// The last thing the surface or the tab did, for the window.
    private(set) var lastEvent = "Nothing yet"
    /// Whether a pinch is under way on the surface.
    private(set) var isPinched = false

    /// The coast under way, on the station's clock.
    private(set) var coastRun: CoastRun?

    @ObservationIgnored private var coastTrace: InteractionTrace?
    @ObservationIgnored private var release = ReleaseVelocity()
    @ObservationIgnored private var scrollStart = 0.0
    @ObservationIgnored private var carryStart: SIMD3<Float>?
    @ObservationIgnored private var lengthAtMagnify: Double?
    @ObservationIgnored private var lengthAtTabDrag: Double?
    @ObservationIgnored private var flashSerial = 0
    @ObservationIgnored private let clockStart = ContinuousClock.now

    /// How long a surface may be, in meters.
    static let lengths = 0.3...1.8
    /// How far toward the viewer a carried surface stands, in meters.
    static let carriedLift: Float = 0.03

    var windowContent: some View { PressStationWindow(station: self) }
    var spaceContent: some View { PressStationSpace(station: self) }
    var tuningContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            TuningPanel(press, title: "Press")
            Divider()
            TuningPanel(lift, title: "Lift")
            Divider()
            TuningPanel(coast, title: "Coast")
            Divider()
            TuningPanel(holdWatch, title: "Hold watch")
        }
    }

    /// The press's tuning as the adapter takes it, its lift its own panel's.
    var pressTuning: SurfacePress.Tuning {
        var tuning = press.tuning
        tuning.lift = lift.tuning
        return tuning
    }

    /// Seconds since the station was made, the clock its coasts run on.
    func now() -> Double {
        (ContinuousClock.now - clockStart) / .seconds(1)
    }

    /// Where the playhead shows at `time`: where a coast under way has it,
    /// or where it stands.
    func playheadShown(at time: Double) -> Double {
        coastRun?.position(at: time) ?? playhead
    }

    // MARK: The press

    /// A pinch touched the surface: a coast under way stops where it shows,
    /// and the pinch is its catch, no tap, while it still went fast enough.
    func catchCoast() -> Bool {
        guard let run = coastRun else { return false }
        let time = now()
        let caught = run.position(at: time)
        let catches = run.pinchCatches(at: time)
        let speed = abs(run.coast.velocity(at: time - run.startTime))
        playhead = caught
        coastRun = nil
        coastTrace?.event("caught", String(format: "at %.3f m, still going %.2f m/s", caught, speed))
        coastTrace?.finish(catches ? "caught" : "stopped by a pinch, almost at rest: the pinch is a tap")
        coastTrace = nil
        return catches
    }

    /// Why a pickup can't come now, when the window says to refuse them.
    func pickUpRefusal() -> String? {
        refusesPickUps ? "the window refuses pickups" : nil
    }

    func pinchUnderWay(_ underWay: Bool) {
        isPinched = underWay
    }

    /// Does what the surface's press was told.
    func perform(_ event: SurfacePressEvent) {
        switch event.action {
        case .tap(let along):
            markers.append(min(max(along, 0), length))
            markers = Array(markers.suffix(8))
            lastEvent = String(format: "Tap at %.2f m: a marker", along)
        case .beginDragAlong(_, let to):
            playhead = min(max(to, 0), length)
            lastEvent = "Drag along: the playhead follows the pinch"
        case .moveDragAlong(let to):
            playhead = min(max(to, 0), length)
        case .endDragAlong:
            lastEvent = String(format: "Drag along ended at %.2f m", playhead)
        case .ignoreDragAcross:
            lastEvent = "Drag across: nothing"
        case .giveUpHold:
            if !event.press.isPickedUp { lastEvent = "Moved off: no pickup or hold" }
        case .pickUp:
            lastEvent = "Picked up: move 2 cm to carry it"
        case .putDown:
            lastEvent = "Put down where it was"
        case .fireHold:
            showFlash("Held")
            lastEvent = "Held a full second"
        case .endHold:
            break
        case .beginScroll(let handMoved):
            scrollStart = playhead
            release = ReleaseVelocity(tuning: coast.tuning)
            scroll(by: handMoved)
            lastEvent = "Scrolling the playhead: flick to coast"
        case .moveScroll(let handMoved):
            scroll(by: handMoved)
        case .endScroll(let coasting):
            endScroll(coasting: coasting)
        case .endCatch:
            lastEvent = String(format: "Caught the coast at %.2f m", playhead)
        case .beginCarry(_, let handMoved):
            if refusesCarries {
                event.refuseCarry(because: "the window refuses carries")
                lastEvent = "Carry refused"
                return
            }
            carryStart = center
            carry(by: handMoved)
            lastEvent = "Carrying the surface"
        case .moveCarry(let handMoved):
            carry(by: handMoved)
        case .endCarry:
            // Let go, it settles back the 3 cm it stood nearer as it was
            // carried, where the hand left it.
            center.z -= Self.carriedLift
            carryStart = nil
            lastEvent = "Dropped where it was carried"
        case .cancelCarry:
            if let carryStart { center = carryStart }
            carryStart = nil
            lastEvent = "Carry cancelled: back where it was"
        }
    }

    /// A two-handed pinch on the surface stretches it about its middle.
    func magnify(_ magnify: SurfaceMagnify) {
        switch magnify {
        case .began:
            lengthAtMagnify = length
            lastEvent = "Two hands: stretching"
        case .changed(let magnification):
            guard let start = lengthAtMagnify, magnification.isFinite else { return }
            setLength(start * magnification, keepingLeftEnd: false)
        case .ended:
            lengthAtMagnify = nil
            lastEvent = String(format: "Stretched to %.2f m", length)
        }
    }

    private func scroll(by handMoved: SIMD3<Double>) {
        let along = scrollStart + handMoved.x
        release.record(along, at: now())
        playhead = min(max(along, 0), length)
    }

    /// The scroll was let go, `coasting` on as its release's speed says, or
    /// cancelled, stopping where it is.
    private func endScroll(coasting: Bool) {
        let time = now()
        let velocity = release.velocity(at: time)
        guard coasting, let run = CoastRun(releasedAt: velocity, from: playhead, at: time, within: 0...length, tuning: coast.tuning) else {
            lastEvent = String(format: "Let go at %.2f m, %.2f m/s: no coast", playhead, velocity)
            return
        }
        coastRun = run
        let traced = trace.begin("Coast", title: "Flick of the playhead")
        traced?.event("set out", String(format: "from %.3f m at %.2f m/s, to rest at %.3f m in %.2f s", run.start, velocity, run.end, run.coast.duration))
        coastTrace = traced
        lastEvent = String(format: "Coasting from %.2f m/s", velocity)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(run.coast.duration))
            guard let self, self.coastRun == run else { return }
            self.playhead = run.end
            self.coastRun = nil
            self.coastTrace?.finish(String(format: "came to rest at %.3f m", run.end))
            self.coastTrace = nil
        }
    }

    private func carry(by handMoved: SIMD3<Double>) {
        guard let carryStart else { return }
        center = carryStart + SIMD3<Float>(handMoved) + SIMD3(0, 0, Self.carriedLift)
    }

    // MARK: The tab

    /// The tab's own drag began: the surface's length follows it.
    func tabDragChanged(byMeters meters: Double) {
        if lengthAtTabDrag == nil { lengthAtTabDrag = length }
        guard let start = lengthAtTabDrag else { return }
        setLength(start + meters, keepingLeftEnd: true)
    }

    func tabDragEnded() {
        guard lengthAtTabDrag != nil else { return }
        lengthAtTabDrag = nil
        lastEvent = String(format: "The tab's drag made the surface %.2f m", length)
    }

    func tabTapped() {
        lastEvent = "The tab was tapped"
        showFlash("Tab tapped")
    }

    /// The tab was held still long enough: it flashes, and its drag and tap
    /// do nothing for the rest of the pinch.
    func tabHeld() -> Bool {
        showFlash("Tab held")
        lastEvent = "The tab was held: its drag and tap do nothing now"
        return true
    }

    /// Puts the surface back as it began: in front, a meter long, its
    /// playhead near its start, and no markers.
    func resetSurface() {
        coastRun = nil
        coastTrace?.finish("the surface was reset")
        coastTrace = nil
        center = LabSpace.front
        length = 1
        playhead = 0.3
        markers = []
        lastEvent = "The surface was reset"
    }

    // MARK: Helpers

    private func setLength(_ newLength: Double, keepingLeftEnd: Bool) {
        let fitted = min(max(newLength, Self.lengths.lowerBound), Self.lengths.upperBound)
        if keepingLeftEnd {
            center.x += Float((fitted - length) / 2)
        }
        length = fitted
        playhead = min(playhead, length)
        markers = markers.filter { $0 <= length }
    }

    private func showFlash(_ text: String) {
        flashSerial += 1
        let serial = flashSerial
        flash = (text, serial)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, self.flash?.serial == serial else { return }
            self.flash = nil
        }
    }
}

#if DEBUG
extension PressStation {
    /// The lab load's drag along the surface (`LabLoad`): the playhead moved
    /// to `along`, as each step of a scroll moves it.
    func loadScrollStep(to along: Double) {
        playhead = min(max(along, 0), length)
    }

    /// The lab load's flick (`LabLoad`): the playhead let go moving at
    /// `velocity`, in meters a second, coasting as a scroll let go does.
    func loadFlick(at velocity: Double) {
        let time = now()
        release = ReleaseVelocity(tuning: coast.tuning)
        release.record(playhead - velocity * 0.05, at: time - 0.05)
        release.record(playhead, at: time)
        endScroll(coasting: true)
    }
}
#endif
