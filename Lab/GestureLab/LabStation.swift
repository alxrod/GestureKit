import GestureKit
import SwiftUI

/// One gesture's station in GestureLab: what the window shows of it, what
/// the immersive space shows of it, its tuning, and its trace.
///
/// A station is a class the registry (`LabStations`) makes once, so its
/// tuning and trace last while another station is chosen. The window shows
/// its title and summary in the list, and, for the chosen one, its
/// `windowContent`, its `tuningContent`, and its trace (`TraceView`); the
/// space shows its `spaceContent`, a `RealityView` with attachments, made
/// afresh each time it's chosen. Its gestures write to `trace`, and read its
/// tuning live from a `TuningStore` named "GestureLab.<id>":
///
///     @MainActor @Observable
///     final class CarryStation: LabStation {
///         let id = "carry"
///         let title = "Carry"
///         let summary = "A panel carried by its grab handle, 1:1 with the hand."
///         let tuning = TuningStore<CarryTuning>(namespace: "GestureLab.carry")
///         let trace = TraceRecorder(logsSummariesPublicly: true)
///
///         static func registerComponents() {
///             // Each RealityKit component and system its space uses.
///         }
///
///         var windowContent: some View { Text("Pinch the handle under the panel and carry it.") }
///         var spaceContent: some View { CarrySpace(station: self) }
///         var tuningContent: some View { TuningPanel(tuning, title: "Carry") }
///     }
@MainActor
protocol LabStation: AnyObject {
    associatedtype WindowContent: View
    associatedtype SpaceContent: View
    associatedtype TuningContent: View

    /// Stable, in lowercase words joined by hyphens, "trace-check": what
    /// the lab remembers the chosen station by, and the end of its tuning's
    /// namespace.
    var id: String { get }

    /// Its name in the list, a word or two.
    var title: String { get }

    /// What it shows, in one line.
    var summary: String { get }

    /// What its gestures write each interaction to.
    var trace: TraceRecorder { get }

    /// What the window shows above its tuning: how to try it, and anything
    /// it wants to show as it's tried.
    @ViewBuilder var windowContent: WindowContent { get }

    /// What the immersive space shows while it's chosen: a `RealityView`
    /// with attachments, standing around `LabSpace.front`.
    @ViewBuilder var spaceContent: SpaceContent { get }

    /// Its tuning panels, a `TuningPanel` for each tuning it has.
    @ViewBuilder var tuningContent: TuningContent { get }

    /// Registers every RealityKit component and system its space uses, its
    /// own and GestureKit's, as the app starts, before anything uses them.
    static func registerComponents()
}

extension LabStation {
    static func registerComponents() {}

    /// `windowContent`, whatever its type, for the window.
    var windowView: AnyView { AnyView(windowContent) }

    /// `spaceContent`, whatever its type, for the space.
    var spaceView: AnyView { AnyView(spaceContent) }

    /// `tuningContent`, whatever its type, for the window.
    var tuningView: AnyView { AnyView(tuningContent) }
}
