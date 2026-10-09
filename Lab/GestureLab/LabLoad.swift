#if DEBUG
@_spi(PinchStandIn) import GestureKit
import os
import RealityKit
import SwiftUI

private let labLoadLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "LabLoad")

/// A load the lab puts on itself, as a hand trying a station would, for
/// measuring in the simulator, which can't pinch: `-labLoad <kinds>` at
/// launch, comma-separated, with `-station <id>` choosing the station it
/// works on. Each begins three seconds in, once the space and the windows
/// stand, and runs until the app quits; measure the app's CPU meanwhile.
///
/// - `trace`: the chosen station's trace filled with 30 interactions of 15
///   events, as after a while of trying it, then a pinch's events written at
///   20 a second, a new pinch every 15.
/// - `tuning`: the chosen station's first number slid back and forth across
///   its range, as a slider dragged, its value set 60 times a second.
/// - `pull`: the pluck's card pulled out of item after item, moving 90 times
///   a second for 2 s each, as a pull's drag moves it.
/// - `scroll`: the pluck's grid scrolled up and down its length at 1,500 pt
///   a second, as a flick moves it.
/// - `drag`: the press's playhead moved along its surface 90 times a second,
///   as a drag along it scrolls it.
/// - `coast`: the press's playhead flicked every 2 s, coasting in between.
/// - `switch`: the next station chosen every 4 s, as the window's list does.
/// - `surface`: a stand-in pinch (`PinchStandIn`) dragged along the press's
///   surface through `.surfacePress`, 90 words a second for 2 s, then let
///   go, again and again, as a hand scrolling it would.
/// - `tab`: a stand-in pinch held on the press's tab through `.holdWatch`,
///   wavering within its stillness, 90 words a second for 2 s, then let go.
/// - `handle`: a stand-in pinch carrying the middle panel of carry and face
///   by its handle through `.grabHandleCarry`, round a circle 20 cm across,
///   90 words a second for 2 s, then let go.
enum LabLoad: String, CaseIterable {
    case trace
    case tuning
    case pull
    case scroll
    case drag
    case coast
    case `switch`
    case surface
    case tab
    case handle

    /// The loads `-labLoad` asked for at launch.
    static let asked: Set<LabLoad> = {
        let given = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["labLoad"] as? String ?? ""
        return Set(given.split(separator: ",").compactMap { LabLoad(rawValue: String($0)) })
    }()

    /// Starts each load asked for on the chosen station, except the scroll,
    /// which its grid starts (`labLoadScrolls()`).
    @MainActor static func start(on lab: LabModel) {
        guard !asked.isEmpty else { return }
        let station = lab.chosen
        if !asked.isDisjoint(with: [.surface, .tab, .handle]) {
            PinchStandIn.shared.isListening = true
        }
        labLoadLogger.info("Lab load \(asked.map(\.rawValue).sorted().joined(separator: ","), privacy: .public) on the station \(station.id, privacy: .public)")
        for load in asked where load != .scroll {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                switch load {
                case .trace: await traceLoad(on: station.trace)
                case .tuning: await tuningLoad(on: station)
                case .pull: await pullLoad(on: station)
                case .drag: await dragLoad(on: station)
                case .coast: await coastLoad(on: station)
                case .switch: await switchLoad(on: lab)
                case .surface: await standInLoad(.surfacePress) { time in SIMD3(300 * time, 0, 0) }
                case .tab: await standInLoad(.holdWatch) { time in SIMD3(4 * sin(time * 9), 3 * cos(time * 7), 0) }
                case .handle: await handleLoad(on: station)
                case .scroll: break
                }
            }
        }
    }

    @MainActor private static func traceLoad(on recorder: TraceRecorder) async {
        let detail = "(3.0 across, -12.0 down, 30.0 toward you) pt: still within its hold's stillness"
        for number in 1...30 {
            let trace = recorder.begin("Load", title: "Earlier pinch \(number)")
            for _ in 0..<15 { trace?.event("drag", detail) }
            trace?.finish("tap")
        }
        var trace = recorder.begin("Load", title: "Pinch under way")
        var written = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            trace?.event("drag", detail, measure: TraceMeasure(Double(written % 15) * 2, "pt", decimals: 1))
            written += 1
            if written % 15 == 0 {
                trace?.finish("pull")
                trace = recorder.begin("Load", title: "Pinch under way")
            }
        }
    }

    @MainActor private static func tuningLoad(on station: any LabStation) async {
        switch station {
        case let station as TraceCheckStation: await slide(station.tuning)
        case let station as CarryAndFaceStation: await slide(station.carry)
        case let station as BelowTheGazeStation: await slide(station.placement)
        case let station as PressStation: await slide(station.press)
        case let station as PluckStation: await slide(station.tuning)
        default: labLoadLogger.error("Lab load tuning: the station \(station.id, privacy: .public) has no tuning it knows")
        }
    }

    /// Slides `store`'s first number across its range and back every 3 s.
    @MainActor private static func slide<Tuning: Tunable>(_ store: TuningStore<Tuning>) async {
        guard let parameter = Tuning.parameters.first(where: { !$0.isSwitch }) else { return }
        let range = parameter.range
        var time = 0.0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            time += 1.0 / 60
            let share = (1 - cos(time * 2 * .pi / 3)) / 2
            store.set(.number(range.lowerBound + share * (range.upperBound - range.lowerBound)), for: parameter)
        }
    }

    @MainActor private static func pullLoad(on station: any LabStation) async {
        guard let station = station as? PluckStation else {
            labLoadLogger.error("Lab load pull: choose the pluck station")
            return
        }
        var item = 1
        while !Task.isCancelled {
            let start = LabSpace.front + SIMD3(0, 0, 0.3)
            station.handle(.lifted, item: item)
            station.handle(.pullBegan(start), item: item)
            for frame in 1...180 {
                try? await Task.sleep(for: .milliseconds(11))
                let angle = Float(frame) / 90 * .pi
                station.handle(.pullMoved(start + SIMD3(cos(angle) * 0.2 - 0.2, sin(angle) * 0.1, 0)), item: item)
            }
            station.handle(.pullEnded(start), item: item)
            station.handle(.settled, item: item)
            if station.cards.count >= 4 { station.clearCards() }
            item = item % station.itemCount + 1
        }
    }

    /// Stand-in pinches on `adapter`, each moved as `moved` says at each of
    /// its seconds, 90 words a second for 2 s, then let go, a fifth of a
    /// second apart.
    @MainActor private static func standInLoad(
        _ adapter: PinchStandIn.Adapter,
        handle: Entity? = nil,
        meters: (Double) -> SIMD3<Float> = { _ in .zero },
        moved: (Double) -> SIMD3<Double>
    ) async {
        var reported = false
        while !Task.isCancelled {
            for frame in 1...180 {
                try? await Task.sleep(for: .milliseconds(11))
                let time = Double(frame) / 90
                let took = PinchStandIn.shared.step(adapter, .moved(points: moved(time), meters: meters(time), handle: handle))
                if !reported {
                    reported = true
                    labLoadLogger.info("Lab load: \(took) adapters take the stand-in's steps as \(String(describing: adapter), privacy: .public)")
                }
            }
            PinchStandIn.shared.step(adapter, .released)
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    @MainActor private static func handleLoad(on station: any LabStation) async {
        guard let station = station as? CarryAndFaceStation, let handle = station.loadHandle() else {
            labLoadLogger.error("Lab load handle: choose the carry and face station")
            return
        }
        // Round a circle 20 cm across, from where it touched, a meter being
        // 1,360 of the handle's points.
        let circle = { (time: Double) -> SIMD3<Float> in
            let angle = Float(time) * .pi
            return SIMD3(cos(angle) * 0.1 - 0.1, sin(angle) * 0.1, 0)
        }
        await standInLoad(.grabHandleCarry, handle: handle, meters: circle) { time in
            let meters = circle(time)
            return SIMD3(Double(meters.x), -Double(meters.y), Double(meters.z)) * 1360
        }
    }

    @MainActor private static func switchLoad(on lab: LabModel) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            let index = lab.stations.firstIndex { $0.id == lab.chosenID } ?? 0
            lab.chosenID = lab.stations[(index + 1) % lab.stations.count].id
            labLoadLogger.info("Lab load switch: chose \(lab.chosenID, privacy: .public)")
        }
    }

    @MainActor private static func dragLoad(on station: any LabStation) async {
        guard let station = station as? PressStation else {
            labLoadLogger.error("Lab load drag: choose the press station")
            return
        }
        var time = 0.0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(11))
            time += 1.0 / 90
            station.loadScrollStep(to: station.length * (1 - cos(time * 2 * .pi / 3)) / 2)
        }
    }

    @MainActor private static func coastLoad(on station: any LabStation) async {
        guard let station = station as? PressStation else {
            labLoadLogger.error("Lab load coast: choose the press station")
            return
        }
        var velocity = 1.5
        while !Task.isCancelled {
            station.loadScrollStep(to: velocity > 0 ? 0.1 : station.length - 0.1)
            station.loadFlick(at: velocity)
            velocity = -velocity
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

extension View {
    /// The scroll load, on a scroll view, when `-labLoad scroll` asks for it;
    /// nothing otherwise.
    func labLoadScrolls() -> some View {
        modifier(LabLoadScroll())
    }
}

/// Scrolls the scroll view it's on down its length and back, at 1,500 pt a
/// second, 60 steps a second.
private struct LabLoadScroll: ViewModifier {
    @State private var position = ScrollPosition(edge: .top)

    func body(content: Content) -> some View {
        if LabLoad.asked.contains(.scroll) {
            content
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height - geometry.containerSize.height
                } action: { _, end in
                    scrollEnd = end
                }
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    var y: CGFloat = 0
                    var step: CGFloat = 1500.0 / 60
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(16))
                        y += step
                        if y >= scrollEnd || y <= 0 {
                            step = -step
                            y = min(max(y, 0), scrollEnd)
                        }
                        position.scrollTo(y: y)
                    }
                }
        } else {
            content
        }
    }

    @State private var scrollEnd: CGFloat = 0
}
#endif
