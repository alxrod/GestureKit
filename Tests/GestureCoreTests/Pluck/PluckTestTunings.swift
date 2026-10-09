@testable import GestureCore

extension PluckTuning {
    /// The tuning the pluck first shipped with, whose press's end settles a
    /// lifted item: what the moved tests prove the rules still do.
    static let firstShipped = PluckTuning(pressEndSettlesLiftedItem: true)
}
