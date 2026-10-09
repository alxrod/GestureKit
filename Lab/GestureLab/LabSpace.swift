import SwiftUI

/// Where the lab's stations stand in the immersive space, whose origin is
/// on the floor where the person stood as it opened, facing −z.
enum LabSpace {
    /// A meter ahead, a little below a standing person's eyes: where a
    /// station's content stands unless it places itself.
    static let front = SIMD3<Float>(0, 1.3, -1)
}

/// The lab's immersive space: the chosen station's space content, made
/// afresh as another station is chosen.
struct LabSpaceView: View {
    let lab: LabModel

    var body: some View {
        ZStack {
            lab.chosen.spaceView
                .id(lab.chosenID)
        }
        .onAppear { lab.isSpaceOpen = true }
        .onDisappear { lab.isSpaceOpen = false }
    }
}
