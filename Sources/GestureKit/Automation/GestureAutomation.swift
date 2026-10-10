#if os(visionOS) && DEBUG
import Foundation
import GestureCore
import os
import RealityKit
import SwiftUI

let gestureAutomationLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "GestureAutomation")

/// What a command came to: its outcome in a word or two, "spawned",
/// "carried", "hold", and what it found, for an agent to assert on.
public struct GestureAutomationAnswer: Sendable {
    public var outcome: String
    public var result: AutomationJSON

    public init(_ outcome: String, _ result: AutomationJSON = .null) {
        self.outcome = outcome
        self.result = result
    }
}

/// GestureKit's automation, in debug builds: drives every gesture as a hand
/// would, through the hand's stand-in (`PinchStandIn`), so an agent can test
/// an app's gestures in the simulator with no one to pinch. A command names
/// a gesture and what it's on, "pluck item 7", and the automation says the
/// words that gesture's adapter would hear, at a hand's pace, and answers
/// with what happened: its outcome, what the adapters reported, each
/// interaction their traces recorded meanwhile, and the app's state.
/// `docs/automation-design.md` has the commands, and what each runs for real
/// and what it stands in for.
///
/// Every app on GestureKit has it, with no code of its own: each adapter
/// registers what it drives as its view appears, under the ids the app
/// already gives it, and goes as its view does. A pluckable item is driven
/// by its title or its id, a pluckable grid, a surface's press, and a hold
/// watch by their `automationID`, a grab handle `GrabHandle.make` made by
/// what it carries, a panel `GazePanel` stood by its entity's name, and a
/// tuning store by its namespace. It's off until asked for, by the launch,
/// `-GestureKitAutomation YES`, or the environment, `GESTUREKIT_AUTOMATION=1`,
/// which GestureKit reads as its first adapter appears, or by
/// `GestureAutomation.start()`; then it answers on 127.0.0.1, port 48765
/// unless `-GestureKitAutomationPort` or `GESTUREKIT_AUTOMATION_PORT` says
/// otherwise, which a visionOS simulator shares with its Mac, and
/// `gesturekit-drive`, the package's driver, talks to. A release build
/// compiles none of it.
///
/// An app may add commands of its own, its state, and what keeps it busy:
///
///     #if DEBUG
///     GestureAutomation.shared.register(state: "editor") { ["clips": .number(Double(clips.count))] }
///     #endif
@MainActor
public final class GestureAutomation {
    /// The automation every adapter reports to.
    public static let shared = GestureAutomation()

    /// The port it answers on unless asked otherwise.
    public static let defaultPort: UInt16 = 48765

    /// Whether it's on.
    public static var isOn: Bool { shared.isEnabled }

    /// Whether it's on: the stand-in listens, and every adapter, handle,
    /// panel, and tuning registers as it appears or is made.
    public private(set) var isEnabled = false

    /// The port it answers on, once it serves.
    public private(set) var port: UInt16?

    /// A tuning store, as the automation tunes it, whatever its tuning.
    struct TuningEntry {
        let namespace: String
        let keys: () -> [String]
        let value: (String) -> TuningValue?
        let isSwitch: (String) -> Bool?
        let set: (String, TuningValue) -> Void
        let reset: () -> Void
        let tuned: () -> [String: TuningValue]
    }

    /// A panel the app stood below a gaze, which `place` stands again.
    struct Panel {
        weak var entity: Entity?
        var tuning: PlacementTuning
        weak var recorder: TraceRecorder?
    }

    /// A grab handle, by the name it's driven by.
    struct Handle {
        weak var entity: Entity?
        let since: ContinuousClock.Instant
    }

    /// A command an app adds.
    struct AppCommand {
        let keys: [String]
        let help: String
        let run: (AutomationArguments) async throws -> GestureAutomationAnswer
    }

    /// A trace an app named, beside those the adapters write to.
    struct NamedTrace {
        weak var recorder: TraceRecorder?
    }

    private var namedTraces: [String: NamedTrace] = [:]
    var handles: [String: Handle] = [:]
    var panels: [String: Panel] = [:]
    private(set) var tunings: [String: TuningEntry] = [:]
    private(set) var appCommands: [String: AppCommand] = [:]
    private var states: [(name: String, read: () -> AutomationJSON)] = []
    private var busyChecks: [(name: String, isBusy: () -> Bool)] = []

    /// What the adapters reported while the command under way ran.
    var log = AutomationEventLog()
    /// When the command under way began; nil between commands, when no one
    /// listens to what the adapters report.
    private var commandStart: ContinuousClock.Instant?
    /// When anything last registered or went, which settling waits on.
    private var changedAt = ContinuousClock.now
    /// The command before, which the next waits for.
    private var tail: Task<Void, Never>?
    private var server: GestureAutomationServer?
    /// Whether the launch has been read for the switch.
    private var readTheLaunch = false

    private init() {}

    // MARK: Turning it on

    /// Turns it on should the launch or the environment ask, once:
    /// `-GestureKitAutomation YES` or `GESTUREKIT_AUTOMATION=1` serves on the
    /// default port, or the one `-GestureKitAutomationPort` or
    /// `GESTUREKIT_AUTOMATION_PORT` gives; `-GestureKitAutomationScript
    /// <file>` or `GESTUREKIT_AUTOMATION_SCRIPT` runs a script of commands.
    /// Every adapter calls it as it appears, and GestureKit's types as
    /// they're made, so an app needs no code; an app that shows no adapter
    /// at launch can call `start()` instead.
    public static func startIfAsked() {
        shared.readLaunch()
    }

    /// Turns it on and serves on `port`, or the one the launch asked for, or
    /// the default, whatever the launch says.
    public static func start(port: UInt16? = nil) {
        shared.readLaunch()
        shared.enable()
        if shared.server == nil {
            shared.serve(port: port ?? GestureAutomationSwitch.read().port ?? defaultPort)
        }
    }

    private func readLaunch() {
        guard !readTheLaunch else { return }
        readTheLaunch = true
        let asked = GestureAutomationSwitch.read()
        guard asked.isOn || asked.script != nil else { return }
        enable()
        if asked.isOn { serve(port: asked.port ?? Self.defaultPort) }
        if let script = asked.script { runScript(at: URL(fileURLWithPath: script)) }
    }

    private func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        PinchStandIn.shared.earsChanged = { [weak self] in self?.registrationsChanged() }
        gestureAutomationLogger.info("GestureKit's automation is on: each adapter registers what it drives as it appears")
    }

    private func serve(port: UInt16) {
        let server = GestureAutomationServer { request in
            await GestureAutomation.shared.answer(request)
        }
        do {
            try server.start(port: port)
            self.server = server
            self.port = port
        } catch {
            gestureAutomationLogger.error("The automation's server couldn't start on port \(port, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Registering

    /// Adds a command of the app's own, `name`, taking `keys`, described by
    /// `help`, as GestureLab adds choosing a station.
    public func register(
        command name: String,
        takes keys: [String],
        help: String,
        _ run: @escaping @MainActor (AutomationArguments) async throws -> GestureAutomationAnswer
    ) {
        appCommands[name] = AppCommand(keys: keys, help: help, run: run)
    }

    /// Adds `name` to the app's state, which every answer carries, as
    /// `read` gives it then.
    public func register(state name: String, _ read: @escaping @MainActor () -> AutomationJSON) {
        states.removeAll { $0.name == name }
        states.append((name, read))
    }

    /// Adds something of the app's that `wait` waits for while `isBusy`
    /// says so, as a coast it runs.
    public func register(busy name: String, _ isBusy: @escaping @MainActor () -> Bool) {
        busyChecks.removeAll { $0.name == name }
        busyChecks.append((name, isBusy))
    }

    /// Names a trace no adapter writes to, whose interactions every answer
    /// carries too; the adapters' own traces are known as they appear.
    public func register(trace recorder: TraceRecorder, named name: String) {
        namedTraces[name] = NamedTrace(recorder: recorder)
    }

    /// Drives a grab handle as `name`, in place of the name it had, as for
    /// a handle whose carried thing's id says nothing to a person.
    public func register(handle: Entity, named name: String) {
        guard isEnabled else { return }
        handles = handles.filter { $0.value.entity != nil && $0.value.entity !== handle }
        handles[name] = Handle(entity: handle, since: .now)
        registrationsChanged()
    }

    /// Registers a tuning store, as it's made, by its namespace.
    func noteTuning<Tuning: Tunable>(_ store: TuningStore<Tuning>) {
        readLaunch()
        guard isEnabled else { return }
        tunings[store.namespace] = TuningEntry(
            namespace: store.namespace,
            keys: { Tuning.parameters.map(\.key) },
            value: { [weak store] key in
                guard let store, let parameter = Tuning.parameter(withKey: key) else { return nil }
                return store.value(of: parameter)
            },
            isSwitch: { key in Tuning.parameter(withKey: key)?.isSwitch },
            set: { [weak store] key, value in
                guard let store, let parameter = Tuning.parameter(withKey: key) else { return }
                store.set(value, for: parameter)
            },
            reset: { [weak store] in store?.resetToDefaults() },
            tuned: { [weak store] in store?.tuning.tunedValues ?? [:] }
        )
        registrationsChanged()
    }

    /// Registers a grab handle `GrabHandle.make` made, under `name`, unless
    /// it's registered already.
    func noteHandle(_ handle: Entity, named name: String) {
        readLaunch()
        guard isEnabled, !handles.values.contains(where: { $0.entity === handle }) else { return }
        handles = handles.filter { $0.value.entity != nil }
        handles[name] = Handle(entity: handle, since: .now)
        registrationsChanged()
    }

    /// Registers a panel `GazePanel` stood below a gaze, by its name, with
    /// the placement and trace it was stood with, so `place` stands it again
    /// the same way.
    func notePanel(_ panel: Entity, tuning: PlacementTuning, recorder: TraceRecorder?) {
        readLaunch()
        guard isEnabled else { return }
        let name = panel.name.isEmpty ? "panel" : panel.name
        let isNew = panels[name]?.entity !== panel
        panels[name] = Panel(entity: panel, tuning: tuning, recorder: recorder ?? panels[name]?.recorder)
        if isNew { registrationsChanged() }
    }

    private func registrationsChanged() {
        changedAt = .now
    }

    /// The handles on screen: made, and in a scene, by their names.
    func liveHandles() -> [(name: String, entity: Entity, since: ContinuousClock.Instant)] {
        handles.compactMap { name, handle in
            guard let entity = handle.entity, entity.scene != nil else { return nil }
            return (name, entity, handle.since)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The panels on screen, by their names.
    func livePanels() -> [(name: String, panel: Panel, entity: Entity)] {
        panels.compactMap { name, panel in
            guard let entity = panel.entity, entity.scene != nil else { return nil }
            return (name, panel, entity)
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: Settling

    /// Whether the app has settled: something is listening, and nothing has
    /// registered or gone for `quiet` seconds.
    func isSettled(quiet: Double = 0.7) -> Bool {
        !PinchStandIn.shared.listening.isEmpty && ContinuousClock.now - changedAt >= .seconds(quiet)
    }

    /// Waits until the app has settled, as after a launch or a change of
    /// what's on screen, for at most `limit` seconds.
    public func settle(quiet: Double = 0.7, atMost limit: Double = 15) async {
        let deadline = ContinuousClock.now + .seconds(limit)
        while !isSettled(quiet: quiet), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// What's busy now: each adapter with a pinch under way, or anything it
    /// began still running, and each of the app's busy checks that says so.
    func busyNow() -> [String] {
        var busy: [String] = []
        for ear in PinchStandIn.shared.listening where ear.latest.isBusy?() == true {
            busy.append("\(gestureAutomationKind(of: ear.adapter)) \(ear.name ?? "unnamed")")
        }
        for check in busyChecks where check.isBusy() {
            busy.append(check.name)
        }
        return busy.sorted()
    }

    // MARK: Hearing the adapters

    /// Whether a command is under way, so the adapters' reports are kept.
    var isListeningToAdapters: Bool { commandStart != nil }

    /// `source` reported `name` on `target`, with `detail`, while a command
    /// ran; nothing otherwise, the detail never worked out.
    func heard(_ source: String, on target: String, _ name: String, _ detail: @autoclosure () -> AutomationJSON = .null) {
        guard let commandStart else { return }
        let time = (ContinuousClock.now - commandStart) / .seconds(1)
        log.record(AutomationEvent(time: time, source: source, target: target, name: name, detail: detail()))
    }

    // MARK: Commands

    /// Runs `request`, a command's JSON, after any before it, and answers.
    public func perform(_ request: AutomationJSON) async -> AutomationJSON {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await self.execute(request)
        }
        tail = Task { @MainActor in _ = await task.value }
        return await task.value
    }

    /// Answers an HTTP request: a command posted, or the state, the
    /// targets, or the help got.
    func answer(_ request: AutomationHTTPRequest) async -> AutomationHTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/state"):
            return AutomationHTTPResponse(json: await perform(["command": "state"]))
        case ("GET", "/targets"):
            return AutomationHTTPResponse(json: await perform(["command": "targets"]))
        case ("GET", "/"), ("GET", "/help"):
            return AutomationHTTPResponse(json: await perform(["command": "help"]))
        case ("POST", _):
            guard let json = try? AutomationJSON.decoded(from: request.body) else {
                return AutomationHTTPResponse(status: 400, json: ["ok": false, "error": "The body isn't JSON: post a command, as {\"command\": \"targets\"}."])
            }
            return AutomationHTTPResponse(json: await perform(json))
        default:
            return AutomationHTTPResponse(status: 405, json: ["ok": false, "error": "Post a command's JSON to /, or get /state, /targets, or /help."])
        }
    }

    private func execute(_ request: AutomationJSON) async -> AutomationJSON {
        let started = ContinuousClock.now
        let startDate = Date.now
        let arguments: AutomationArguments
        do {
            arguments = try AutomationArguments(request)
        } catch {
            return ["ok": false, "error": .string(String(describing: error))]
        }
        let marks = traceMarks()
        log = AutomationEventLog()
        commandStart = started
        var object: [String: AutomationJSON]
        do {
            let done = try await run(arguments)
            object = [
                "ok": true,
                "command": .string(arguments.command),
                "outcome": .string(done.outcome),
                "result": done.result,
            ]
            gestureAutomationLogger.info("Automation: \(arguments.command, privacy: .public) → \(done.outcome, privacy: .public)")
        } catch {
            let reason = String(describing: error)
            object = ["ok": false, "command": .string(arguments.command), "error": .string(reason)]
            gestureAutomationLogger.info("Automation: \(arguments.command, privacy: .public) failed: \(reason)")
        }
        commandStart = nil
        if !["state", "help", "trace", "targets", "smoke"].contains(arguments.command) {
            object["events"] = log.json
            object["trace"] = .array(interactions(since: marks, began: startDate))
            object["app"] = appState()
        }
        object["elapsed"] = .number((ContinuousClock.now - started) / .seconds(1), decimals: 3)
        return .object(object)
    }

    /// Runs a command, GestureKit's or the app's, with what it was given.
    func run(_ arguments: AutomationArguments) async throws -> GestureAutomationAnswer {
        if let drive = GestureAutomation.builtIn[arguments.command] {
            try arguments.refuseOthers(than: drive.keys)
            return try await drive.run(self, arguments)
        }
        if let command = appCommands[arguments.command] {
            try arguments.refuseOthers(than: command.keys)
            return try await command.run(arguments)
        }
        let names = (Array(GestureAutomation.builtIn.keys) + Array(appCommands.keys)).sorted().joined(separator: ", ")
        throw AutomationError("No command “\(arguments.command)”; there are \(names). \"help\" says what each takes.")
    }

    // MARK: Traces

    /// Every trace it knows: those the adapters on screen and the panels
    /// write to, and those the app named, each once.
    func knownTraces() -> [TraceRecorder] {
        var seen: Set<ObjectIdentifier> = []
        var recorders: [TraceRecorder] = []
        let candidates = PinchStandIn.shared.listening.compactMap(\.latest.recorder)
            + panels.values.compactMap(\.recorder)
            + namedTraces.values.compactMap(\.recorder)
        for recorder in candidates where seen.insert(ObjectIdentifier(recorder)).inserted {
            recorders.append(recorder)
        }
        return recorders
    }

    /// The newest interaction's number in each trace it knows.
    private func traceMarks() -> [ObjectIdentifier: Int] {
        Dictionary(uniqueKeysWithValues: knownTraces().map { (ObjectIdentifier($0), $0.interactions.map(\.id).max() ?? 0) })
    }

    /// Each interaction begun after `marks`, or, in a trace it didn't know
    /// then, after `began`, oldest first.
    private func interactions(since marks: [ObjectIdentifier: Int], began: Date) -> [AutomationJSON] {
        var found: [(Date, AutomationJSON)] = []
        for recorder in knownTraces() {
            let mark = marks[ObjectIdentifier(recorder)]
            for interaction in recorder.interactions where mark.map({ interaction.id > $0 }) ?? (interaction.date >= began) {
                found.append((interaction.date, gestureAutomationJSON(interaction)))
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The app's state, as each part it registered gives it.
    func appState() -> AutomationJSON {
        .object(Dictionary(states.map { ($0.name, $0.read()) }, uniquingKeysWith: { _, last in last }))
    }
}

/// What the launch or the environment asks of the automation.
struct GestureAutomationSwitch {
    var isOn = false
    var port: UInt16?
    var script: String?

    /// Reads `-GestureKitAutomation`, `-GestureKitAutomationPort`, and
    /// `-GestureKitAutomationScript` from the launch, and
    /// `GESTUREKIT_AUTOMATION`, `GESTUREKIT_AUTOMATION_PORT`, and
    /// `GESTUREKIT_AUTOMATION_SCRIPT` from the environment, as a simulator's
    /// launch passes them (`SIMCTL_CHILD_GESTUREKIT_AUTOMATION=1`).
    static func read(
        arguments: [String: Any] = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> GestureAutomationSwitch {
        func text(_ argument: String, _ variable: String) -> String? {
            if let value = arguments[argument] { return "\(value)" }
            return environment[variable]
        }
        var asked = GestureAutomationSwitch()
        if let on = text("GestureKitAutomation", "GESTUREKIT_AUTOMATION") {
            asked.isOn = ["1", "yes", "true", "on"].contains(on.trimmingCharacters(in: .whitespaces).lowercased())
        }
        asked.port = text("GestureKitAutomationPort", "GESTUREKIT_AUTOMATION_PORT").flatMap { UInt16($0.trimmingCharacters(in: .whitespaces)) }
        if asked.port != nil { asked.isOn = true }
        asked.script = text("GestureKitAutomationScript", "GESTUREKIT_AUTOMATION_SCRIPT").flatMap { $0.isEmpty ? nil : $0 }
        return asked
    }
}

/// An interaction a trace recorded, as an answer gives it.
@MainActor
func gestureAutomationJSON(_ interaction: TracedInteraction) -> AutomationJSON {
    var object: [String: AutomationJSON] = [
        "id": .number(Double(interaction.id)),
        "gesture": .string(interaction.gesture),
        "title": .string(interaction.title),
        "outcome": interaction.outcome.map { .string($0) } ?? .null,
        "summary": .string(interaction.summary),
        "events": .array(interaction.events.map { event in
            [
                "name": .string(event.name),
                "time": .number(gestureAutomationSeconds(event.offset), decimals: 3),
                "count": .number(Double(event.count)),
                "detail": .string(event.detailText),
            ]
        }),
    ]
    if let lasted = interaction.lasted { object["lasted"] = .number(gestureAutomationSeconds(lasted), decimals: 3) }
    if interaction.isAlarm { object["alarm"] = true }
    return .object(object)
}

/// A duration in seconds.
func gestureAutomationSeconds(_ duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
}

/// An adapter's kind, as the automation's words name it.
func gestureAutomationKind(of adapter: PinchStandIn.Adapter) -> String {
    switch adapter {
    case .surfacePress: "surface"
    case .holdWatch: "tab"
    case .grabHandleCarry: "carry"
    case .pluckItem: "item"
    case .pluckContainer: "grid"
    }
}
#endif
