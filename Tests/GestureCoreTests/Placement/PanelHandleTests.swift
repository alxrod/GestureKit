import Testing
@testable import GestureCore

/// The handle under a panel that stands with no window bar of its own: its
/// look and reach, in points, as the panel is drawn.
@Suite struct PanelHandleTests {
    /// A pill as visionOS's window bar is, 128 by 16 pt, its top 12 pt below
    /// the panel's bottom edge, centered under it.
    @Test func itsAPillJustUnderThePanel() {
        #expect(PlacementTuning.standard.handleSize == SIMD2(128, 16))
        #expect(PlacementTuning.standard.handleGap == 12)
        #expect(PanelHandle.middle(belowPanelOfHeight: 300) == -(150 + 12 + 8))
        #expect(PanelHandle.middle(belowPanelOfHeight: 362) == -(181 + 12 + 8))
    }

    /// A panel not measured yet, or measured as nothing, puts it just under
    /// the panel's middle, never above it.
    @Test(arguments: [0.0, -40, .nan, -.infinity])
    func aPanelOfNoHeightPutsItUnderItsMiddle(height: Double) {
        #expect(PanelHandle.middle(belowPanelOfHeight: height) == -(12 + 8))
    }

    /// It takes looks and pinches over 60 pt from the panel's bottom edge
    /// down, the least a target should, and 22 pt beyond either end of the
    /// pill: from the edge, never over the panel, whose own controls take
    /// theirs, to 32 pt below the pill's foot.
    @Test func itTakesLooksAndPinchesOverMoreThanItDraws() {
        let reach = PanelHandle.reach()
        #expect(reach == SIMD2(172, 60))
        #expect(PanelHandle.reachOffset() == -10)
        let height = 300.0
        let middle = PanelHandle.middle(belowPanelOfHeight: height)
        let reachMiddle = middle + PanelHandle.reachOffset()
        // Its top is the panel's bottom edge.
        #expect(abs(reachMiddle + reach.y / 2 - -height / 2) < 1e-9)
        // It covers the pill, with room below and to either side.
        #expect(reachMiddle - reach.y / 2 < middle - PlacementTuning.standard.handleSize.y / 2)
        #expect(reach.x > PlacementTuning.standard.handleSize.x)
        #expect(abs(reachMiddle - reach.y / 2 - (middle - 8 - 32)) < 1e-9)
    }

    /// Tuned otherwise, its reach still begins at the panel's bottom edge,
    /// however big the pill and its gap.
    @Test func tunedOtherwiseItsReachStillBeginsAtThePanelsEdge() {
        let tuning = PlacementTuning(handleSize: SIMD2(200, 24), handleGap: 20, handleReachBeyondEnds: 10, handleReachHeight: 80)
        let reach = PanelHandle.reach(tuning: tuning)
        #expect(reach == SIMD2(220, 80))
        let height = 400.0
        let middle = PanelHandle.middle(belowPanelOfHeight: height, tuning: tuning)
        #expect(middle == -(200 + 20 + 12))
        let reachMiddle = middle + PanelHandle.reachOffset(tuning: tuning)
        #expect(abs(reachMiddle + reach.y / 2 - -height / 2) < 1e-9)
    }
}
