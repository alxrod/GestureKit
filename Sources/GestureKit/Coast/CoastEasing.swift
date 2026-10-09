#if os(visionOS)
import GestureCore
import SwiftUI

/// A coast as a SwiftUI animation: as far along its change, at each time, as
/// the coast has gone of its distance (`Coast.progress(at:)`), over its
/// duration, so whatever a scroll moved, and any fades that follow it, slow
/// as the coast does, exponentially, which no timing curve does.
///
///     withAnimation(Animation(CoastEasing(coast))) {
///         offset = run.end
///     }
///
/// A pinch that catches the coast sets where it stands at once, from the
/// run's position at the touch (`CoastRun.position(at:)`), which ends this
/// where it is.
public struct CoastEasing: CustomAnimation {
    /// The coast it eases by.
    public let coast: Coast

    public init(_ coast: Coast) {
        self.coast = coast
    }

    public nonisolated func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < coast.duration else { return nil }
        return value.scaled(by: coast.progress(at: time))
    }
}
#endif
