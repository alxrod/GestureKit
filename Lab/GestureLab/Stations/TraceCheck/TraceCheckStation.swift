import GestureKit
import RealityKit
import SwiftUI

/// The trace check's one tunable value, which proves a tuning reaches the
/// space live.
struct TraceCheckTuning: Tunable {
    /// The cube's edge, in meters.
    var size: Double

    init(size: Double = 0.2) {
        self.size = size
    }

    static let defaults = TraceCheckTuning()

    static let parameters: [TuningParameter<TraceCheckTuning>] = [
        .number(\.size, key: "size", title: "Size", unit: "m", range: 0.05...0.6, step: 0.01),
    ]
}

/// Marks the trace check's cube, the one entity its drag takes a pinch on.
struct TraceCheckTarget: Component {}

/// The station that proves the lab end to end: a cube in the space to
/// pinch, each pinch traced from its touch to its release, and its size,
/// tuned in the window, applied as the slider moves. A pinch let go within
/// a centimeter of where it touched is a tap, which counts and turns the
/// cube another color; one that moves farther is a drag.
@MainActor @Observable
final class TraceCheckStation: LabStation {
    let id = "trace-check"
    let title = "Trace check"
    let summary = "A cube to pinch: each pinch traced, its size tuned live."
    let tuning = TuningStore<TraceCheckTuning>(namespace: "GestureLab.trace-check")
    let trace = TraceRecorder(logsSummariesPublicly: true)

    /// How many taps the cube has had.
    private(set) var taps = 0

    /// The pinch under way: its trace, where it began and touched, and
    /// whether it has gone a centimeter from there.
    @ObservationIgnored private var press: Press?

    private struct Press {
        let trace: InteractionTrace?
        let began: SIMD3<Float>
        let touched: SIMD3<Float>
        var wentFar = false
    }

    /// How far a pinch may move, in meters, and still be a tap.
    private let tapReach: Float = 0.01

    static func registerComponents() {
        TraceCheckTarget.registerComponent()
    }

    var windowContent: some View { TraceCheckWindow(station: self) }
    var spaceContent: some View { TraceCheckSpace(station: self) }
    var tuningContent: some View { TuningPanel(tuning, title: "Trace check") }

    /// A pinch on the cube, begun at `start`, moved to `point`, both in the
    /// space, in meters; its first move is its touch. A pinch begun
    /// elsewhere while one is under way means that one's end went unseen,
    /// as when the system cancels a drag, so it ends as nothing first.
    func pinchMoved(to point: SIMD3<Float>, from start: SIMD3<Float>) {
        if let press, simd_distance(press.began, start) > 0.0001 {
            press.trace?.finish("nothing: its end went unseen")
            self.press = nil
        }
        guard var press else {
            let trace = self.trace.begin(title, title: "Pinch on the cube")
            trace?.event("touch", "size \(formatted(tuning.tuning.size)) m")
            self.press = Press(trace: trace, began: start, touched: point)
            return
        }
        if !press.wentFar, simd_distance(point, press.touched) >= tapReach {
            press.wentFar = true
            press.trace?.event("moved", "past \(formatted(Double(tapReach) * 100, decimals: 0)) cm")
            self.press = press
        }
    }

    /// A pinch on the cube let go at `point`.
    func pinchEnded(at point: SIMD3<Float>) {
        guard let press else { return }
        self.press = nil
        let moved = simd_distance(point, press.touched)
        press.trace?.event("release", "moved \(formatted(Double(moved) * 100, decimals: 1)) cm")
        if moved < tapReach {
            taps += 1
            press.trace?.finish("tap")
        } else {
            press.trace?.finish("drag")
        }
    }

    private func formatted(_ number: Double, decimals: Int = 2) -> String {
        number.formatted(.number.precision(.fractionLength(decimals)))
    }
}

/// The trace check's part of the window: how to try it, and the count.
private struct TraceCheckWindow: View {
    let station: TraceCheckStation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pinch the cube in front of you. Let go where you touched and it's a tap, which counts and changes its color; move a centimeter or more and it's a drag. Each pinch shows in the trace, and Size changes the cube as the slider moves.")
                .font(.system(size: 20))
            Text(station.taps == 1 ? "1 tap" : "\(station.taps) taps")
                .font(.system(size: 28, weight: .bold).monospacedDigit())
        }
    }
}

/// The trace check's part of the space: the cube, with its count above it.
private struct TraceCheckSpace: View {
    let station: TraceCheckStation

    private static let colors: [UIColor] = [.systemTeal, .systemPink, .systemYellow, .systemGreen, .systemPurple]

    var body: some View {
        let size = Float(station.tuning.tuning.size)
        let taps = station.taps
        RealityView { content, attachments in
            let cube = ModelEntity(
                mesh: .generateBox(size: 1, cornerRadius: 0.08),
                materials: [SimpleMaterial(color: Self.colors[0], isMetallic: false)]
            )
            cube.name = "trace-check-cube"
            cube.position = LabSpace.front
            cube.scale = SIMD3(repeating: size)
            cube.components.set(TraceCheckTarget())
            cube.components.set(InputTargetComponent())
            // A unit box, scaled with the cube.
            cube.components.set(CollisionComponent(shapes: [.generateBox(size: [1, 1, 1])]))
            cube.components.set(HoverEffectComponent())
            content.add(cube)
            if let count = attachments.entity(for: "count") {
                count.position = Self.countPosition(above: size)
                content.add(count)
            }
        } update: { content, attachments in
            guard let cube = content.entities.first(where: { $0.name == "trace-check-cube" }) as? ModelEntity else { return }
            cube.scale = SIMD3(repeating: size)
            cube.model?.materials = [SimpleMaterial(color: Self.colors[taps % Self.colors.count], isMetallic: false)]
            attachments.entity(for: "count")?.position = Self.countPosition(above: size)
        } attachments: {
            Attachment(id: "count") {
                Text(taps == 1 ? "1 tap" : "\(taps) taps")
                    .font(.system(size: 36, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .glassBackgroundEffect()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToEntity(where: .has(TraceCheckTarget.self))
                .onChanged { value in
                    station.pinchMoved(
                        to: value.convert(value.location3D, from: .local, to: .scene),
                        from: value.convert(value.startLocation3D, from: .local, to: .scene)
                    )
                }
                .onEnded { value in
                    station.pinchEnded(at: value.convert(value.location3D, from: .local, to: .scene))
                }
        )
    }

    /// Where the count stands: 6 cm above the cube's top.
    private static func countPosition(above size: Float) -> SIMD3<Float> {
        LabSpace.front + SIMD3(0, size / 2 + 0.06, 0)
    }
}
