// The README's code for Lift, compiled with the lab so it can't rot.
// ReadmeSnippetsTests checks the README shows exactly the code below.

import GestureKit
import SwiftUI

/// A photo that lifts off its page while it's held, drawn a little way
/// along as the pinch tugs it.
struct LiftingPhoto: View {
    let isHeld: Bool
    /// How far the pinch has tugged it, in its points, x across, y down,
    /// z toward the viewer.
    let tug: SIMD3<Double>

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.indigo)
            .frame(width: 300, height: 300)
            .liftFollowEffect(isHeld ? tug : .zero)
            .liftEffect(isHeld, style: LiftStyle(scale: 1.08, depth: 36))
            .raisedWhileLifted(isHeld)
    }
}
