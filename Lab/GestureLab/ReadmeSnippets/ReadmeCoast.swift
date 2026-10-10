// The README's code for Coast, compiled with the lab so it can't rot.
// ReadmeSnippetsTests checks the README shows exactly the code below.

import GestureKit
import SwiftUI

/// A strip of tiles scrolled by the hand, coasting on as it's let go on the
/// move, until a pinch catches it.
@MainActor @Observable
final class CoastingStrip {
    /// How far it has scrolled, in meters, from 0 to 2.
    var offset = 0.0

    @ObservationIgnored private var run: CoastRun?
    @ObservationIgnored private var release = ReleaseVelocity()
    @ObservationIgnored private var scrollStart = 0.0
    @ObservationIgnored private let clockStart = ContinuousClock.now

    /// Seconds on the strip's own clock, which its coasts run on.
    private func now() -> Double {
        (ContinuousClock.now - clockStart) / .seconds(1)
    }

    /// A pinch touched the strip: a coast still on the move stops where it
    /// is, and the pinch is that catch, not a tap.
    func catchCoast() -> Bool {
        let time = now()
        guard let run, !run.isOver(at: time) else { return false }
        self.run = nil
        // Set without an animation, which ends the coast's.
        offset = run.position(at: time)
        return run.pinchCatches(at: time)
    }

    func perform(_ event: SurfacePressEvent) {
        switch event.action {
        case .beginScroll(let handMoved):
            scrollStart = offset
            release = ReleaseVelocity()
            scroll(by: handMoved)
        case .moveScroll(let handMoved):
            scroll(by: handMoved)
        case .endScroll(coasting: true):
            let time = now()
            guard let run = CoastRun(releasedAt: release.velocity(at: time), from: offset, at: time, within: 0...2) else { return }
            self.run = run
            withAnimation(Animation(CoastEasing(run.coast))) {
                offset = run.end
            }
        default:
            break
        }
    }

    private func scroll(by handMoved: SIMD3<Double>) {
        offset = min(max(scrollStart - handMoved.x, 0), 2)
        release.record(offset, at: now())
    }
}

struct CoastingStripView: View {
    let strip: CoastingStrip
    @Environment(\.physicalMetrics) private var metrics

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<40, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(.mint)
                    .frame(width: 96, height: 96)
            }
        }
        .offset(x: -metrics.convert(strip.offset, from: .meters))
        .frame(width: 800, alignment: .leading)
        .clipped()
        .surfacePress(canPickUp: false, dragAlongScrolls: true, catchCoast: { strip.catchCoast() }) { event in
            strip.perform(event)
        }
    }
}
