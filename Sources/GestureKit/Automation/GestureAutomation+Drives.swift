#if os(visionOS) && DEBUG
import Foundation
import GestureCore
import RealityKit
import simd

/// GestureKit's own commands, each driving a gesture's adapter through the
/// hand's stand-in at a hand's pace, or reading what's registered.
extension GestureAutomation {
    /// A built-in command: the arguments it takes, what it does in a line,
    /// and its drive.
    struct Drive {
        let keys: [String]
        let help: String
        let run: @MainActor (GestureAutomation, AutomationArguments) async throws -> GestureAutomationAnswer
    }

    static let builtIn: [String: Drive] = [
        "help": Drive(keys: [], help: "Lists the commands, what each takes, and what it does.") { automation, _ in
            GestureAutomationAnswer("help", automation.helpJSON())
        },
        "targets": Drive(keys: [], help: "Lists what's drivable now, by kind and id: grids, items made, surfaces, tabs, handles, and panels, each with its default command.") { automation, _ in
            GestureAutomationAnswer(automation.isSettled() ? "ready" : "settling", automation.targetsJSON())
        },
        "state": Drive(keys: [], help: "The targets, the tunings and their values, the traces, what's busy, and the app's state.") { automation, _ in
            GestureAutomationAnswer(automation.isSettled() ? "ready" : "settling", automation.stateJSON())
        },
        "smoke": Drive(keys: [], help: "Drives every target on screen once with its default command, a grid's first item for its items, and reports each outcome. Outcome: passed or failed.") { automation, _ in
            try await automation.smoke()
        },
        "pluck": Drive(
            keys: ["target", "item", "hold", "pull", "pullTime", "carry", "carryTime"],
            help: "Pinches the item (its title or id), holds it still for hold s (its hold + 0.1), pulls the hand by pull m ([0, 0, 0.05], toward you) over pullTime s (0.4), carries what broke free by carry m over carryTime s (0.4), and lets go. Outcome: spawned, lifted, stayed down, tapped, or nothing."
        ) { automation, arguments in try await automation.pluck(arguments) },
        "tap": Drive(
            keys: ["target", "item", "surface", "at"],
            help: "Taps an item (its title or id), or a surface, at m along its leading edge (0.1). Outcome: tapped, or tap."
        ) { automation, arguments in try await automation.tap(arguments) },
        "scroll": Drive(
            keys: ["target", "grid", "by", "to", "on", "time"],
            help: "Scrolls a pluckable grid (the only one) by pt (400; more is further down), or to top, end, an offset, or an item's title or id, over time s (0.5); with on, the pinch starts on that item. Outcome: scrolled."
        ) { automation, arguments in try await automation.scroll(arguments) },
        "carry": Drive(
            keys: ["target", "handle", "by", "to", "time", "ending"],
            help: "Carries a grab handle by m ([0.1, 0, 0]), or its carried thing's middle to a point m in its parent's frame, over time s (0.6), and lets go, or, with ending cancelled, has its gesture cancelled there instead. Outcome: carried, nothing, under nothing, or refused; its result's ending says how the carry ended, released or cancelled."
        ) { automation, arguments in try await automation.carry(arguments) },
        "place": Drive(
            keys: ["target", "panel", "head"],
            help: "Stands a panel the app stood below a gaze (the only one) below a gaze again: head tracker (as the app would, untracked in the simulator), untracked, or {\"at\": [x, y, z], \"yaw\": deg right, \"pitch\": deg up}. Outcome: placed."
        ) { automation, arguments in try await automation.place(arguments) },
        "drag": Drive(
            keys: ["target", "surface", "along", "across", "at", "time"],
            help: "Drags on a surface (the only one), from at m (0.1), along m (0.3) and across m up (0), over time s (0.6), comes to rest for 0.2 s, and lets go. Outcome: scroll, drag along, or drag across."
        ) { automation, arguments in try await automation.dragSurface(arguments, flick: false) },
        "flick": Drive(
            keys: ["target", "surface", "along", "at", "time"],
            help: "Flicks a surface along m (0.25) over time s (0.12), let go on the move, which the app may coast on. Outcome: scroll."
        ) { automation, arguments in try await automation.dragSurface(arguments, flick: true) },
        "pickup": Drive(
            keys: ["target", "surface", "by", "at", "time"],
            help: "Holds a surface still past its pickup, then carries it by m ([0.1, 0.05, 0.05]) over time s (0.5), and lets go. Outcome: carry, or pickup, put down with by [0, 0, 0]."
        ) { automation, arguments in try await automation.pickUp(arguments) },
        "hold": Drive(
            keys: ["target", "surface", "tab", "seconds", "waver", "moveFirst"],
            help: "Holds a surface, or a tab watched for a hold, still for seconds (its hold + 0.2), wavering waver pt (1.5), after moving by moveFirst m, and lets go. Outcome: hold, the control's, or let go before its hold."
        ) { automation, arguments in try await automation.hold(arguments) },
        "tune": Drive(
            keys: ["target", "tuning", "key", "value", "reset"],
            help: "Sets key of a tuning (its store's namespace, or a unique end of it) to value, as its slider does, or puts it back to its defaults with reset true. Outcome: tuned."
        ) { automation, arguments in try automation.tune(arguments) },
        "trace": Drive(
            keys: ["gesture", "clear"],
            help: "Reads every trace's interactions, newest first, or only gesture's (\"Pluck\", \"Press\", \"Carry\", \"HoldWatch\", \"Placement\"); with clear true, clears every trace after."
        ) { automation, arguments in
            let gesture = try arguments.string("gesture")
            let recorders = automation.knownTraces()
            let read = recorders.flatMap(\.interactions)
                .filter { gesture == nil || $0.gesture == gesture }
                .sorted { $0.date > $1.date }
                .map { gestureAutomationJSON($0) }
            if try arguments.bool("clear") == true {
                for recorder in recorders { recorder.clear() }
            }
            return GestureAutomationAnswer("read", ["interactions": .array(read)])
        },
        "wait": Drive(
            keys: ["timeout", "quiet"],
            help: "Waits until no adapter has a pinch under way, nothing it began still runs, and nothing of the app's is busy, for quiet s (0.3), at most timeout s (10). Outcome: idle."
        ) { automation, arguments in
            let waited = try await automation.waitUntilIdle(timeout: try arguments.number("timeout") ?? 10, quiet: try arguments.number("quiet") ?? 0.3)
            return GestureAutomationAnswer("idle", ["waited": .number(waited, decimals: 3)])
        },
    ]

    // MARK: Pluck

    private func pluck(_ arguments: AutomationArguments) async throws -> GestureAutomationAnswer {
        let asked = try targetName(arguments, "item", example: "item 7")
        let ear = try itemEar(asked)
        let title = ear.name ?? asked
        let holdDuration = ear.latest.facts?()["holdDuration"]?.number ?? 0.25
        let hold = try arguments.number("hold") ?? holdDuration + 0.1
        let pull = try arguments.vector("pull") ?? SIMD3(0, 0, 0.05)
        let pullTime = try arguments.number("pullTime") ?? 0.4
        let carry = try arguments.vector("carry") ?? .zero
        let carryTime = try arguments.number("carryTime") ?? 0.4
        let item = PinchStandIn.Adapter.pluckItem(title)

        let pressed = ContinuousClock.now
        PinchStandIn.shared.step(item, .pressDown)
        await automationPause(until: hold, from: pressed)
        // A hand that holds for the lift waits to see it before it pulls,
        // however late its count comes on a busy main actor.
        if hold >= holdDuration {
            let deadline = ContinuousClock.now + .seconds(1.5)
            while !log.contains("lifted", from: "pluck", on: title), ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        let start = ContinuousClock.now
        var path = AutomationPath.steps(from: .zero, to: pull, over: pullTime)
        if carry != .zero {
            path += AutomationPath.steps(from: pull, to: pull + carry, over: carryTime).map { AutomationPath.Step(time: pullTime + $0.time, point: $0.point) }
        }
        // The drag speaks as SwiftUI's would: only once the hand has gone
        // its start for the stage the pinch is in, held back or brought
        // down at the lift, and only while it's let in.
        var dragSpoke = false
        for step in path where step.point != .zero {
            await automationPause(until: step.time, from: start)
            let points = AutomationPath.points(ofMeters: step.point)
            let drag = ear.latest.facts?()["dragNow"]
            let minimum = drag?["start"]?.number ?? 0
            guard drag?["letIn"]?.bool ?? true, AutomationPath.dragSpeaks(at: points, minimumDistance: minimum, hasSpoken: dragSpoke) else { continue }
            dragSpoke = true
            PinchStandIn.shared.step(item, .dragMoved(points: points))
        }
        try? await Task.sleep(for: .milliseconds(30))
        // Let go: the drag's end and its reset, if it spoke, the press's
        // end, and the tap.
        if dragSpoke {
            PinchStandIn.shared.step(item, .dragEnded)
            PinchStandIn.shared.step(item, .dragStopped)
        }
        PinchStandIn.shared.step(item, .pressUp)
        PinchStandIn.shared.step(item, .tapped)
        await untilIdle(ear, atMost: 1.5)
        // The grid's scroll view, given its scroll back, takes a frame or two.
        await untilIdle(kind: .pluckContainer, atMost: 1)
        try? await Task.sleep(for: .milliseconds(200))

        let names = log.names(from: "pluck", on: title)
        var result: [String: AutomationJSON] = [
            "item": .string(title),
            "lifted": .bool(names.contains("lifted")),
            "settled": .bool(names.contains("settled")),
            "dragSpoke": .bool(dragSpoke),
            "reported": .array(names.map { .string($0) }),
        ]
        if let spawned = log.lastDetail(of: "spawned", from: "pluck", on: title) { result["spawnedAt"] = spawned["at"] ?? .null }
        if let carried = log.lastDetail(of: "carried", from: "pluck", on: title) { result["carriedTo"] = carried["middle"] ?? .null }
        if let released = log.lastDetail(of: "released", from: "pluck", on: title) { result["releasedAt"] = released["at"] ?? .null }
        if let grid = try? gridEar(nil).0.latest.facts?() { result["grid"] = grid }
        return GestureAutomationAnswer(AutomationOutcome.pluck(names), .object(result))
    }

    // MARK: Tap

    private func tap(_ arguments: AutomationArguments) async throws -> GestureAutomationAnswer {
        let item = try arguments.string("item")
        let surface = try arguments.string("surface")
        let target = try arguments.string("target")
        // An item when one is named, or the target names one.
        if let asked = item ?? (surface == nil ? target.flatMap { isItem($0) ? $0 : nil } : nil) {
            let ear = try itemEar(asked)
            let title = ear.name ?? asked
            let adapter = PinchStandIn.Adapter.pluckItem(title)
            PinchStandIn.shared.step(adapter, .pressDown)
            try? await Task.sleep(for: .milliseconds(80))
            PinchStandIn.shared.step(adapter, .pressUp)
            PinchStandIn.shared.step(adapter, .tapped)
            await untilIdle(ear, atMost: 1)
            let names = log.names(from: "pluck", on: title)
            return GestureAutomationAnswer(AutomationOutcome.pluck(names), ["item": .string(title), "reported": .array(names.map { .string($0) })])
        }
        let (ear, name) = try surfaceEar(surface ?? target)
        let touch = try surfaceTouch(arguments)
        PinchStandIn.shared.step(.surfacePress, .moved(points: .zero, touch: touch), named: name)
        try? await Task.sleep(for: .milliseconds(80))
        PinchStandIn.shared.step(.surfacePress, .released, named: name)
        return await surfaceAnswer(ear, name: name)
    }

    // MARK: Scroll

    private func scroll(_ arguments: AutomationArguments) async throws -> GestureAutomationAnswer {
        let (ear, name) = try gridEar(try arguments.string("grid") ?? arguments.string("target"))
        guard let facts = ear.latest.facts?(), let before = facts["offset"]?.array?.compactMap(\.number), before.count == 2 else {
            throw AutomationError("The grid hasn't said where it's scrolled yet; wait a moment and try again.")
        }
        let time = try arguments.number("time") ?? 0.5
        var on = try arguments.string("on")
        if let asked = on { on = try itemEar(asked).name }
        let lowest = facts["minOffset"]?.number ?? 0
        let highest = facts["maxOffset"]?.number ?? 0
        var target: Double
        if let to = try arguments.string("to") {
            switch to {
            case "top": target = lowest
            case "end": target = highest
            default:
                if let offset = Double(to) {
                    target = offset
                } else {
                    return try await scroll(toItem: to, grid: ear, named: name)
                }
            }
        } else {
            target = before[1] + (try arguments.number("by") ?? 400)
        }
        target = min(max(target, lowest), highest)
        try await scrollGrid(name, from: SIMD2(before[0], before[1]), to: target, time: time, on: on)
        let after = ear.latest.facts?()["offset"]?.array?.compactMap(\.number) ?? before
        let landed = after.count == 2 ? after[1] : before[1]
        var result: [String: AutomationJSON] = [
            "grid": .string(name ?? "unnamed"),
            "from": .number(before[1], decimals: 1),
            "to": .number(landed, decimals: 1),
            "asked": .number(target, decimals: 1),
            "scrolledBy": .number(landed - before[1], decimals: 1),
            "canScroll": .bool(highest > lowest),
            "itemsMade": itemsMadeJSON(),
        ]
        if let on {
            let names = log.names(from: "pluck", on: on)
            result["on"] = .string(on)
            result["itemOutcome"] = .string(AutomationOutcome.pluck(names))
        }
        if let grid = ear.latest.facts?() { result["gridNow"] = grid }
        return GestureAutomationAnswer("scrolled", .object(result))
    }

    /// Scrolls the grid named `name` as a pinch would: tracking at its touch,
    /// on `on`'s item if given, interacting as its pan begins, cancelling the
    /// item's press as a pan does, the content moving to `target` over `time`
    /// seconds, then idle.
    private func scrollGrid(_ name: String?, from offset: SIMD2<Double>, to target: Double, time: Double, on: String?) async throws {
        let start = ContinuousClock.now
        if let on { PinchStandIn.shared.step(.pluckItem(on), .pressDown) }
        PinchStandIn.shared.step(.pluckContainer, .scrollPhase(.tracking), named: name)
        await automationPause(until: 0.06, from: start)
        PinchStandIn.shared.step(.pluckContainer, .scrollPhase(.interacting), named: name)
        if let on { PinchStandIn.shared.step(.pluckItem(on), .pressUp) }
        for step in AutomationPath.steps(from: SIMD3(0, offset.y, 0), to: SIMD3(0, target, 0), over: time) {
            await automationPause(until: 0.06 + step.time, from: start)
            PinchStandIn.shared.step(.pluckContainer, .contentScrolled(to: SIMD2(offset.x, step.point.y)), named: name)
        }
        try? await Task.sleep(for: .milliseconds(50))
        PinchStandIn.shared.step(.pluckContainer, .scrollPhase(.idle), named: name)
        // The scroll view's geometry, and the items it makes, after the move.
        try? await Task.sleep(for: .milliseconds(200))
    }

    /// Scrolls the grid until the item `asked` names is made: from the top,
    /// most of a screen at a time, to its end.
    private func scroll(toItem asked: String, grid ear: PinchStandIn.Ear, named name: String?) async throws -> GestureAutomationAnswer {
        func offset() -> SIMD2<Double>? {
            guard let parts = ear.latest.facts?()["offset"]?.array?.compactMap(\.number), parts.count == 2 else { return nil }
            return SIMD2(parts[0], parts[1])
        }
        guard let before = offset() else { throw AutomationError("The grid hasn't said where it's scrolled yet.") }
        if !isItem(asked) {
            let facts = ear.latest.facts?()
            let lowest = facts?["minOffset"]?.number ?? 0
            let highest = facts?["maxOffset"]?.number ?? 0
            let page = max(100, (facts?["viewport"]?.array?.last?.number ?? 600) * 0.8)
            try await scrollGrid(name, from: before, to: lowest, time: 0.2, on: nil)
            while !isItem(asked), let now = offset(), now.y < highest - 0.5 {
                try await scrollGrid(name, from: now, to: min(now.y + page, highest), time: 0.2, on: nil)
            }
        }
        guard isItem(asked) else {
            throw AutomationError("Scrolled to the end of the grid and no item “\(asked)” was made.")
        }
        let after = offset() ?? before
        return GestureAutomationAnswer("scrolled", [
            "grid": .string(name ?? "unnamed"),
            "from": .number(before.y, decimals: 1),
            "to": .number(after.y, decimals: 1),
            "scrolledBy": .number(after.y - before.y, decimals: 1),
            "madeItem": .string(asked),
            "itemsMade": itemsMadeJSON(),
        ])
    }

    // MARK: Carry

    private func carry(_ arguments: AutomationArguments) async throws -> GestureAutomationAnswer {
        let name = try targetName(arguments, "handle", example: "panel-b")
        let live = liveHandles()
        guard let handle = live.first(where: { $0.name == name })?.entity else {
            let names = live.map(\.name).joined(separator: ", ")
            throw AutomationError("No grab handle “\(name)” is on screen; \(names.isEmpty ? "none is" : "there are \(names)").")
        }
        let carried = CarriedEntity.carried(byHandle: handle)
        let by: SIMD3<Double>
        if let given = try arguments.vector("by") {
            by = given
        } else if let to = try arguments.vector("to") {
            guard let carried else { throw AutomationError("The handle “\(name)” carries something only its app can find; give by rather than to.") }
            by = to - SIMD3<Double>(carried.position)
        } else {
            by = SIMD3(0.1, 0, 0)
        }
        let time = try arguments.number("time") ?? 0.6
        let asked = try arguments.string("ending") ?? CarryEnding.released.rawValue
        guard let ending = CarryEnding(rawValue: asked), ending != .viewWent else {
            throw AutomationError("carry ends released or cancelled, not “\(asked)”; its view going is the app's to drive.")
        }
        let from = carried?.position
        let start = ContinuousClock.now
        for step in AutomationPath.steps(from: .zero, to: by, over: time) {
            await automationPause(until: step.time, from: start)
            let took = PinchStandIn.shared.step(.grabHandleCarry, .moved(points: AutomationPath.points(ofMeters: step.point), meters: SIMD3<Float>(step.point), handle: handle))
            if took == 0 { throw AutomationError("No grab handle carry is on screen to take the pinch on “\(name)”.") }
        }
        try? await Task.sleep(for: .milliseconds(20))
        PinchStandIn.shared.step(.grabHandleCarry, ending == .cancelled ? .cancelled : .released)
        await untilIdle(kind: .grabHandleCarry, atMost: 1)
        let names = log.names(from: "carry")
        guard names.contains("touch") else {
            throw AutomationError("No grab handle carry took the pinch on “\(name)”: none on screen takes handles marked as it is.")
        }
        var result: [String: AutomationJSON] = [
            "handle": .string(name),
            "by": .vector(by),
            "reported": .array(names.map { .string($0) }),
        ]
        if let from {
            result["from"] = .vector(from)
            result["asked"] = .vector(SIMD3<Double>(from) + by)
        }
        if let ended = log.lastDetail(of: "end", from: "carry") { result["middle"] = ended["middle"] ?? .null }
        if let ended = log.lastDetail(of: "end", from: "carry") ?? log.lastDetail(of: "release", from: "carry") {
            result["ending"] = ended["ending"] ?? .null
        }
        if let carried {
            result["carried"] = .string(carried.name)
            result["stood"] = .vector(carried.position)
            if let head = HeadTracker.shared.viewerPosition() {
                result["fromTheHead"] = .number(Double(simd_distance(carried.position(relativeTo: nil), head)), decimals: 4)
            }
            result["aboutTheHead"] = .string(CarriedEntity.describe(carried, aboutHeadAt: HeadTracker.shared.viewerPosition()))
        }
        return GestureAutomationAnswer(AutomationOutcome.carry(names), .object(result))
    }

    // MARK: Place

    private func place(_ arguments: AutomationArguments) async throws -> GestureAutomationAnswer {
        let live = livePanels()
        let name: String
        if let given = try arguments.string("panel") ?? arguments.string("target") {
            name = given
        } else {
            guard live.count == 1, let only = live.first else {
                throw AutomationError(live.isEmpty ? "No panel the app stood below a gaze is on screen." : "Name the panel: \(live.map(\.name).joined(separator: ", ")).")
            }
            name = only.name
        }
        guard let found = live.first(where: { $0.name == name }) else {
            throw AutomationError("No panel “\(name)” the app stood below a gaze is on screen; \(live.isEmpty ? "none is" : "there are \(live.map(\.name).joined(separator: ", "))").")
        }
        let head: simd_float4x4?
        let headWords: String
        switch arguments.values["head"] {
        case nil, .null?, .string("tracker")?:
            head = await HeadTracker.shared.headTransform(waitingAtMost: GazePanel.headPatience)
            headWords = head == nil ? "the tracker's, untracked here" : "the tracker's"
        case .string("untracked")?:
            head = nil
            headWords = "untracked"
        case .object(let given)?:
            let at = try AutomationArguments(.object(given.merging(["command": "head"]) { first, _ in first }))
            let place = try at.vector("at") ?? SIMD3<Double>(UntrackedHead.eye)
            let yaw = try at.number("yaw") ?? 0
            let pitch = try at.number("pitch") ?? 0
            head = gestureAutomationHead(at: SIMD3<Float>(place), yawRight: Float(yaw), pitchUp: Float(pitch))
            headWords = String(format: "at (%.2f, %.2f, %.2f) m, %.0f° right, %.0f° up", place.x, place.y, place.z, yaw, pitch)
        default:
            throw AutomationError("place's head is tracker, untracked, or {\"at\": [0, 1.6, 0], \"yaw\": 20, \"pitch\": -30}.")
        }
        let placement = GazePanel.stand(found.entity, forHead: head, tuning: found.panel.tuning, recorder: found.panel.recorder, because: "the automation asked")
        let degrees = { (radians: Float) in AutomationJSON.number(Double(radians * 180 / .pi), decimals: 2) }
        heard("placement", on: name, "placed", ["position": .vector(placement.pose.position)])
        return GestureAutomationAnswer("placed", [
            "panel": .string(name),
            "head": .string(headWords),
            "position": .vector(placement.pose.position),
            "distance": .number(Double(placement.distance), decimals: 4),
            "belowTheGaze": degrees(placement.belowTheGaze),
            "tilt": degrees(placement.tilt),
            "gazeAcross": degrees(placement.gazeAzimuth),
            "gazeUp": degrees(placement.gazeElevation),
        ])
    }

    // MARK: Surfaces and tabs

    private func dragSurface(_ arguments: AutomationArguments, flick: Bool) async throws -> GestureAutomationAnswer {
        let (ear, name) = try surfaceEar(try arguments.string("surface") ?? arguments.string("target"))
        let touch = try surfaceTouch(arguments)
        let along = try arguments.number("along") ?? (flick ? 0.25 : 0.3)
        let across = flick ? 0 : (try arguments.number("across") ?? 0)
        let time = try arguments.number("time") ?? (flick ? 0.12 : 0.6)
        let start = ContinuousClock.now
        PinchStandIn.shared.step(.surfacePress, .moved(points: .zero, touch: touch), named: name)
        for step in AutomationPath.steps(from: .zero, to: SIMD3(along, across, 0), over: time) {
            await automationPause(until: 0.03 + step.time, from: start)
            PinchStandIn.shared.step(.surfacePress, .moved(points: AutomationPath.points(ofMeters: step.point), touch: touch), named: name)
        }
        if !flick {
            // A drag, unlike a flick, comes to rest before it's let go.
            let end = AutomationPath.points(ofMeters: SIMD3(along, across, 0))
            for step in AutomationPath.held(at: end, for: 0.2, wavering: 0) {
                await automationPause(until: 0.03 + time + step.time, from: start)
                PinchStandIn.shared.step(.surfacePress, .moved(points: step.point, touch: touch), named: name)
            }
        }
        PinchStandIn.shared.step(.surfacePress, .released, named: name)
        return await surfaceAnswer(ear, name: name)
    }

    private func pickUp(_ arguments: AutomationArguments) async throws -> GestureAutomationAnswer {
        let (ear, name) = try surfaceEar(try arguments.string("surface") ?? arguments.string("target"))
        let touch = try surfaceTouch(arguments)
        let by = try arguments.vector("by") ?? SIMD3(0.1, 0.05, 0.05)
        let time = try arguments.number("time") ?? 0.5
        let pickUp = (ear.latest.facts?()["pickUpDelay"]?.number ?? 0.5) + 0.15
        let start = ContinuousClock.now
        PinchStandIn.shared.step(.surfacePress, .moved(points: .zero, touch: touch), named: name)
        for step in AutomationPath.held(at: .zero, for: pickUp, wavering: 1.5) {
            await automationPause(until: step.time, from: start)
            PinchStandIn.shared.step(.surfacePress, .moved(points: step.point, touch: touch), named: name)
        }
        if by != .zero {
            for step in AutomationPath.steps(from: .zero, to: by, over: time) {
                await automationPause(until: pickUp + step.time, from: start)
                PinchStandIn.shared.step(.surfacePress, .moved(points: AutomationPath.points(ofMeters: step.point), touch: touch), named: name)
            }
        }
        try? await Task.sleep(for: .milliseconds(30))
        PinchStandIn.shared.step(.surfacePress, .released, named: name)
        return await surfaceAnswer(ear, name: name)
    }

    private func hold(_ arguments: AutomationArguments) async throws -> GestureAutomationAnswer {
        let surface = try arguments.string("surface")
        let tab = try arguments.string("tab")
        let target = try arguments.string("target")
        guard surface == nil || tab == nil else { throw AutomationError("hold takes a surface or a tab, not both.") }
        // A tab when one is named, or the target names one, or no surface is
        // on screen to hold.
        let surfaces = PinchStandIn.shared.listening.filter { $0.adapter == .surfacePress }
        let tabs = PinchStandIn.shared.listening.filter { $0.adapter == .holdWatch }
        let holdsATab = tab != nil
            || (surface == nil && target.map { asked in tabs.contains { $0.answers(to: asked) } && !surfaces.contains { $0.answers(to: asked) } } == true)
            || (surface == nil && target == nil && surfaces.isEmpty)
        let adapter: PinchStandIn.Adapter = holdsATab ? .holdWatch : .surfacePress
        let (ear, name) = holdsATab
            ? try namedEar(.holdWatch, named: tab ?? target, what: "tab watched for a hold")
            : try surfaceEar(surface ?? target)
        let facts = ear.latest.facts?()
        let holdsAfter = holdsATab ? (facts?["duration"]?.number ?? 0.6) : (facts?["holdDuration"]?.number ?? 1)
        let seconds = try arguments.number("seconds") ?? holdsAfter + 0.2
        let waver = try arguments.number("waver") ?? 1.5
        let moveFirst = try arguments.vector("moveFirst") ?? .zero
        let start = ContinuousClock.now
        PinchStandIn.shared.step(adapter, .moved(points: .zero), named: name)
        var at = SIMD3<Double>.zero
        var offset = 0.0
        if moveFirst != .zero {
            for step in AutomationPath.steps(from: .zero, to: moveFirst, over: 0.15) {
                await automationPause(until: step.time, from: start)
                PinchStandIn.shared.step(adapter, .moved(points: AutomationPath.points(ofMeters: step.point)), named: name)
            }
            at = AutomationPath.points(ofMeters: moveFirst)
            offset = 0.15
        }
        for step in AutomationPath.held(at: at, for: max(0, seconds - offset), wavering: waver) {
            await automationPause(until: offset + step.time, from: start)
            PinchStandIn.shared.step(adapter, .moved(points: step.point), named: name)
        }
        await automationPause(until: seconds, from: start)
        PinchStandIn.shared.step(adapter, .released, named: name)
        if !holdsATab { return await surfaceAnswer(ear, name: name) }
        await untilIdle(ear, atMost: 1)
        let names = log.names(from: "hold watch")
        return GestureAutomationAnswer(AutomationOutcome.holdWatch(names), [
            "tab": .string(name ?? "unnamed"),
            "seconds": .number(seconds, decimals: 3),
            "reported": .array(names.map { .string($0) }),
        ])
    }

    /// Where a surface's pinch touches: `at` meters along its leading edge,
    /// 0.1 unless said, and 20 pt down.
    private func surfaceTouch(_ arguments: AutomationArguments) throws -> SIMD2<Double> {
        SIMD2((try arguments.number("at") ?? 0.1) * AutomationPath.pointsPerMeter, 20)
    }

    /// What a pinch on a surface came to, once its press has finished.
    private func surfaceAnswer(_ ear: PinchStandIn.Ear, name: String?) async -> GestureAutomationAnswer {
        await untilIdle(ear, atMost: 1.5)
        let target = name ?? "unnamed"
        let names = log.names(from: "press", on: target)
        var result: [String: AutomationJSON] = [
            "surface": .string(target),
            "reported": .array(names.map { .string($0) }),
        ]
        // A scroll let go may coast, as the app decides; one cancelled stops.
        if let ended = log.lastDetail(of: "endScroll", from: "press", on: target) { result["letGo"] = ended["coasting"] ?? .null }
        if let tap = log.lastDetail(of: "tap", from: "press", on: target) { result["tappedAt"] = tap["along"] ?? .null }
        if let carried = log.lastDetail(of: "moveCarry", from: "press", on: target) { result["handMoved"] = carried["handMoved"] ?? .null }
        return GestureAutomationAnswer(AutomationOutcome.surface(names), .object(result))
    }

    // MARK: Tune

    private func tune(_ arguments: AutomationArguments) throws -> GestureAutomationAnswer {
        let asked = try targetName(arguments, "tuning", example: "pluck")
        let entry = try tuningEntry(asked)
        if try arguments.bool("reset") == true {
            entry.reset()
            return GestureAutomationAnswer("tuned", ["tuning": .string(entry.namespace), "tuned": gestureAutomationJSON(entry.tuned())])
        }
        let key = try arguments.requiredString("key", example: "holdDuration")
        guard let isSwitch = entry.isSwitch(key) else {
            throw AutomationError("\(entry.namespace) has no \(key); it has \(entry.keys().joined(separator: ", ")).")
        }
        let value: TuningValue
        if isSwitch {
            guard let on = try arguments.bool("value") else { throw AutomationError("tune needs value, true or false, for \(key).") }
            value = .toggle(on)
        } else {
            guard let number = try arguments.number("value") else { throw AutomationError("tune needs value, a number, for \(key).") }
            value = .number(number)
        }
        entry.set(key, value)
        return GestureAutomationAnswer("tuned", [
            "tuning": .string(entry.namespace),
            "key": .string(key),
            "value": entry.value(key).map(gestureAutomationJSON) ?? .null,
            "tuned": gestureAutomationJSON(entry.tuned()),
        ])
    }

    /// The tuning `name` names: its namespace, or the one namespace ending
    /// in it after a dot.
    private func tuningEntry(_ name: String) throws -> TuningEntry {
        if let exact = tunings[name] { return exact }
        let matches = tunings.values.filter { $0.namespace.hasSuffix("." + name) }
        guard matches.count == 1, let only = matches.first else {
            let all = tunings.keys.sorted().joined(separator: ", ")
            throw AutomationError(matches.isEmpty
                ? "No tuning “\(name)”; there are \(all.isEmpty ? "none" : all)."
                : "“\(name)” names several tunings; name one: \(matches.map(\.namespace).sorted().joined(separator: ", ")).")
        }
        return only
    }

    // MARK: Smoke

    /// Drives every target on screen once with its default command, and
    /// says what each came to: each grid scrolled and scrolled back, the
    /// first item made plucked, each surface tapped, each tab held, each
    /// handle carried up 5 cm and back, and each panel placed again.
    private func smoke() async throws -> GestureAutomationAnswer {
        await settle(atMost: 10)
        let grids = PinchStandIn.shared.listening.filter { $0.adapter == .pluckContainer }.map { $0.name ?? "unnamed" }.sorted()
        let firstItem = itemTitlesMade().first
        let surfaces = PinchStandIn.shared.listening.filter { $0.adapter == .surfacePress }.map { $0.name ?? "unnamed" }.sorted()
        let tabs = PinchStandIn.shared.listening.filter { $0.adapter == .holdWatch }.map { $0.name ?? "unnamed" }.sorted()
        let handleNames = liveHandles().filter(\.entity.isEnabledInHierarchy).map(\.name)
        let panelNames = livePanels().map(\.name)

        var drives: [AutomationJSON] = []
        func drive(_ kind: String, _ id: String, _ command: AutomationJSON, accepting: [String]) async {
            let saved = log
            log = AutomationEventLog()
            var report: [String: AutomationJSON] = ["kind": .string(kind), "id": .string(id), "command": command]
            do {
                let done = try await run(try AutomationArguments(command))
                report["outcome"] = .string(done.outcome)
                report["passed"] = .bool(accepting.contains(done.outcome))
                if !accepting.contains(done.outcome) {
                    report["expected"] = .array(accepting.map { .string($0) })
                }
            } catch {
                report["passed"] = false
                report["error"] = .string(String(describing: error))
            }
            log = saved
            _ = try? await waitUntilIdle(timeout: 6, quiet: 0.2)
            drives.append(.object(report))
        }

        for grid in grids {
            await drive("grid", grid, ["command": "scroll", "grid": .string(grid), "by": 300], accepting: ["scrolled"])
            await drive("grid", grid, ["command": "scroll", "grid": .string(grid), "to": "top"], accepting: ["scrolled"])
        }
        if let firstItem {
            await drive("item", firstItem, ["command": "pluck", "item": .string(firstItem)], accepting: ["spawned"])
        }
        for surface in surfaces {
            await drive("surface", surface, ["command": "tap", "surface": .string(surface)], accepting: ["tap"])
        }
        for tab in tabs {
            await drive("tab", tab, ["command": "hold", "tab": .string(tab)], accepting: ["hold", "the control's"])
        }
        for handle in handleNames {
            await drive("handle", handle, ["command": "carry", "handle": .string(handle), "by": [0, 0.05, 0]], accepting: ["carried", "refused"])
            await drive("handle", handle, ["command": "carry", "handle": .string(handle), "by": [0, -0.05, 0]], accepting: ["carried", "refused"])
        }
        for panel in panelNames {
            await drive("panel", panel, ["command": "place", "panel": .string(panel)], accepting: ["placed"])
        }
        let failed = drives.filter { $0["passed"] != true }.count
        return GestureAutomationAnswer(drives.isEmpty ? "nothing to drive" : failed == 0 ? "passed" : "failed", [
            "drives": .array(drives),
            "passed": .number(Double(drives.count - failed)),
            "failed": .number(Double(failed)),
        ])
    }

    // MARK: Waiting

    /// Waits until nothing is busy for `quiet` seconds, at most `timeout`
    /// seconds, and says how long it waited.
    func waitUntilIdle(timeout: Double, quiet: Double) async throws -> Double {
        let start = ContinuousClock.now
        var idleSince: ContinuousClock.Instant?
        while true {
            let now = ContinuousClock.now
            let busy = busyNow()
            if busy.isEmpty {
                let since = idleSince ?? now
                idleSince = since
                if now - since >= .seconds(quiet) { return (now - start) / .seconds(1) }
            } else {
                idleSince = nil
            }
            if now - start >= .seconds(timeout) {
                throw AutomationError("Still busy after \(timeout) s: \(busy.joined(separator: ", ")).")
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Waits until `ear`'s adapter has nothing under way, at most `limit`
    /// seconds, then a moment for what it tells to land.
    private func untilIdle(_ ear: PinchStandIn.Ear, atMost limit: Double) async {
        let deadline = ContinuousClock.now + .seconds(limit)
        while ear.latest.isBusy?() == true, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// Waits until every adapter of `kind` has nothing under way.
    private func untilIdle(kind: PinchStandIn.Adapter, atMost limit: Double) async {
        let deadline = ContinuousClock.now + .seconds(limit)
        while PinchStandIn.shared.listening.contains(where: { $0.adapter == kind && $0.latest.isBusy?() == true }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
        try? await Task.sleep(for: .milliseconds(100))
    }

    // MARK: Finding what's driven

    /// What a command is on: its own key's value, or `target`'s.
    private func targetName(_ arguments: AutomationArguments, _ key: String, example: String) throws -> String {
        if let given = try arguments.string(key) ?? arguments.string("target"), !given.isEmpty { return given }
        throw AutomationError("\(arguments.command) needs what it's on, as \(key)=\"\(example)\"; \"targets\" lists them.")
    }

    /// Whether an item `asked` names, by its title or its id, is made now.
    private func isItem(_ asked: String) -> Bool {
        PinchStandIn.shared.listening.contains { ear in
            if case .pluckItem = ear.adapter { return ear.answers(to: asked) }
            return false
        }
    }

    /// The item `asked` names, by its title or its id, made by its grid now.
    private func itemEar(_ asked: String) throws -> PinchStandIn.Ear {
        let found = PinchStandIn.shared.listening.first { ear in
            if case .pluckItem = ear.adapter { return ear.answers(to: asked) }
            return false
        }
        guard let found else {
            let made = itemTitlesMade()
            let range = made.isEmpty ? "none is" : "\(made.first ?? "") to \(made.last ?? "") are"
            throw AutomationError("No item “\(asked)” is made by its grid now (\(range)); scroll to it first: scroll to=\"\(asked)\".")
        }
        return found
    }

    private func surfaceEar(_ name: String?) throws -> (PinchStandIn.Ear, String?) {
        try namedEar(.surfacePress, named: name, what: "surface")
    }

    private func gridEar(_ name: String?) throws -> (PinchStandIn.Ear, String?) {
        try namedEar(.pluckContainer, named: name, what: "pluckable grid")
    }

    /// The adapter of `kind` named `name`, or the only one on screen.
    private func namedEar(_ kind: PinchStandIn.Adapter, named name: String?, what: String) throws -> (PinchStandIn.Ear, String?) {
        let ears = PinchStandIn.shared.listening.filter { $0.adapter == kind }
        let names = ears.map { $0.name ?? "unnamed" }.sorted().joined(separator: ", ")
        if let name {
            let named = ears.filter { $0.answers(to: name) }
            guard let ear = named.first else {
                throw AutomationError("No \(what) “\(name)” is on screen; \(ears.isEmpty ? "none is" : "there are \(names)").")
            }
            if named.count > 1 {
                throw AutomationError("\(named.count) \(what)s on screen are “\(name)”; give each its own automationID.")
            }
            return (ear, name)
        }
        guard ears.count == 1, let only = ears.first else {
            throw AutomationError(ears.isEmpty ? "No \(what) is on screen." : "Several \(what)s are on screen; name one: \(names).")
        }
        return (only, only.name)
    }

    /// The titles of the items their grids have made now, as a lazy grid
    /// makes those in view and a little beyond, in order.
    func itemTitlesMade() -> [String] {
        PinchStandIn.shared.listening.compactMap { ear -> String? in
            if case .pluckItem(let title) = ear.adapter { return title }
            return nil
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func itemsMadeJSON() -> AutomationJSON {
        let made = itemTitlesMade()
        return ["count": .number(Double(made.count)), "first": made.first.map { .string($0) } ?? .null, "last": made.last.map { .string($0) } ?? .null]
    }

    // MARK: Targets, state, and help

    /// What's drivable now, by kind, each with its id and default command.
    func targetsJSON() -> AutomationJSON {
        func ears(_ kind: PinchStandIn.Adapter, default command: String) -> AutomationJSON {
            .array(PinchStandIn.shared.listening.filter { $0.adapter == kind }
                .sorted { ($0.name ?? "") < ($1.name ?? "") }
                .map { ear in
                    var object = ear.latest.facts?().object ?? [:]
                    object["id"] = ear.name.map { .string($0) } ?? .null
                    object["busy"] = .bool(ear.latest.isBusy?() == true)
                    object["default"] = .string(command)
                    return .object(object)
                })
        }
        let items: [AutomationJSON] = PinchStandIn.shared.listening.compactMap { ear in
            guard case .pluckItem(let title) = ear.adapter else { return nil }
            return ["id": .string(title), "appID": ear.latest.id.map { .string($0) } ?? .null, "default": "pluck"]
        }
        .sorted { ($0["id"]?.string ?? "").localizedStandardCompare($1["id"]?.string ?? "") == .orderedAscending }
        let now = ContinuousClock.now
        let handleList: [AutomationJSON] = liveHandles().map { name, entity, since in
            var object: [String: AutomationJSON] = [
                "id": .string(name),
                "entity": .string(entity.name),
                "enabled": .bool(entity.isEnabledInHierarchy),
                "age": .number((now - since) / .seconds(1), decimals: 1),
                "default": "carry",
            ]
            if let carried = CarriedEntity.carried(byHandle: entity) {
                object["carries"] = .string(carried.name)
                object["at"] = .vector(carried.position)
            }
            return .object(object)
        }
        let panelList: [AutomationJSON] = livePanels().map { name, _, entity in
            ["id": .string(name), "at": .vector(entity.position(relativeTo: nil)), "enabled": .bool(entity.isEnabledInHierarchy), "default": "place"]
        }
        return [
            "grids": ears(.pluckContainer, default: "scroll"),
            "items": .array(items),
            "surfaces": ears(.surfacePress, default: "tap"),
            "tabs": ears(.holdWatch, default: "hold"),
            "handles": .array(handleList),
            "panels": .array(panelList),
            "carries": ears(.grabHandleCarry, default: "carry"),
        ]
    }

    func stateJSON() -> AutomationJSON {
        var tuningList: [String: AutomationJSON] = [:]
        for entry in tunings.values {
            var values: [String: AutomationJSON] = [:]
            for key in entry.keys() { values[key] = entry.value(key).map(gestureAutomationJSON) ?? .null }
            tuningList[entry.namespace] = .object(values)
        }
        return [
            "ready": .bool(isSettled()),
            "port": port.map { .number(Double($0)) } ?? .null,
            "targets": targetsJSON(),
            "tunings": .object(tuningList),
            "traces": .number(Double(knownTraces().count)),
            "busy": .array(busyNow().map { .string($0) }),
            "app": appState(),
            "commands": .array((Array(GestureAutomation.builtIn.keys) + Array(appCommands.keys)).sorted().map { .string($0) }),
        ]
    }

    func helpJSON() -> AutomationJSON {
        var commands: [String: AutomationJSON] = [:]
        for (name, drive) in GestureAutomation.builtIn {
            commands[name] = ["takes": .array(drive.keys.map { .string($0) }), "does": .string(drive.help)]
        }
        for (name, command) in appCommands {
            commands[name] = ["takes": .array(command.keys.map { .string($0) }), "does": .string(command.help)]
        }
        return [
            "commands": .object(commands),
            "units": "Vectors are a hand's move in meters, x right, y up, z toward you, as [0, 0, 0.05] or \"0,0,0.05\"; a grid scrolls in points; times are seconds. target names what any command is on.",
            "answer": "Each command answers ok, outcome, result, events (what the adapters reported), trace (what the traces recorded meanwhile), and app (the app's state); a failure answers ok false and error.",
        ]
    }
}

/// Sleeps until `offset` seconds after `start`.
func automationPause(until offset: Double, from start: ContinuousClock.Instant) async {
    try? await Task.sleep(until: start + .seconds(offset), clock: .continuous)
}

/// A tuning's value as JSON.
func gestureAutomationJSON(_ value: TuningValue) -> AutomationJSON {
    switch value {
    case .number(let number): .number(number)
    case .toggle(let isOn): .bool(isOn)
    }
}

/// A tuning's values as JSON, by key.
func gestureAutomationJSON(_ values: [String: TuningValue]) -> AutomationJSON {
    .object(values.mapValues(gestureAutomationJSON))
}

/// A head at `place` in the space, turned `yawRight` degrees to the right of
/// straight ahead, −z, and `pitchUp` degrees up, as world tracking's device
/// anchor gives one.
func gestureAutomationHead(at place: SIMD3<Float>, yawRight: Float, pitchUp: Float) -> simd_float4x4 {
    let yaw = simd_quatf(angle: -yawRight * .pi / 180, axis: SIMD3(0, 1, 0))
    let pitch = simd_quatf(angle: pitchUp * .pi / 180, axis: SIMD3(1, 0, 0))
    var transform = simd_float4x4(yaw * pitch)
    transform.columns.3 = SIMD4(place.x, place.y, place.z, 1)
    return transform
}
#endif
