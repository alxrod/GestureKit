// gesturekit-drive: drives the gestures of any app on GestureKit running in a
// visionOS simulator, through GestureKit's automation, from the Mac. It's a
// Mac tool, shipped with the package, so an app's own repository can run it:
//
//     swift run gesturekit-drive launch com.example.app
//     swift run gesturekit-drive targets
//     swift run gesturekit-drive smoke
//     swift run gesturekit-drive pluck "item 7" pull=0,0,0.06
//
// `gesturekit-drive help` says the rest; docs/automation-design.md has the
// commands and what each runs for real.
#if os(macOS)
import Foundation

@main
struct GestureKitDrive {
    static func main() async {
        var driver = Driver()
        let code = await driver.run(Array(CommandLine.arguments.dropFirst()))
        exit(code)
    }
}

/// Something the driver couldn't do, said in a sentence.
struct DriveError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The driver: its options, and each of its commands.
struct Driver {
    var port = ProcessInfo.processInfo.environment["GESTUREKIT_AUTOMATION_PORT"].flatMap { Int($0) } ?? 48765
    var device = ProcessInfo.processInfo.environment["GESTUREKIT_SIMULATOR"] ?? "booted"
    var printsJSON = false
    var brief = false
    var timeout = 120.0

    static let usage = """
        gesturekit-drive: drive the gestures of an app on GestureKit in a visionOS simulator.

        usage: gesturekit-drive [--port N] [--device NAME|UDID] [--json] [--brief] [--timeout S] <command> …

          launch <bundle-id> [--script FILE] [-- APP ARGUMENTS]
                           relaunch the app in the simulator with GestureKit's automation on
                           (GESTUREKIT_AUTOMATION=1), and wait until it's ready; with --script,
                           run FILE's commands as it settles, and print their results
          targets          list what's drivable now, by kind and id, with each one's default command
          smoke            drive every target once with its default command and report each;
                           exits 1 if any failed
          pluck|tap|scroll|carry|place|drag|flick|pickup|hold|tune [TARGET] [key=value …]
                           drive a gesture and print the app's answer: its outcome, result,
                           events, trace, and app state; exits 1 if it failed
          trace [gesture=NAME] [clear=true]
                           print what the app's traces recorded, newest first
          wait [timeout=S]   wait until nothing is under way
          state            print everything the app has registered
          commands         print the app's commands and what each takes
          send JSON        send any command as JSON
          screenshot [FILE]  save what the simulator shows, as a PNG
          install-skill [--into DIR] [--replace]
                           copy GestureKit's verify-gestures skill, which drives and proves an
                           app's gestures with this tool, into DIR, .agents/skills unless given;
                           refuses to replace one already there unless --replace

        Values: vectors are meters, x right, y up, z toward you, as 0,0,0.05; a grid scrolls
        in points; times are seconds; a value that starts with { or [ is JSON.
        The port is GESTUREKIT_AUTOMATION_PORT, or 48765; the simulator GESTUREKIT_SIMULATOR,
        or the booted one.
        """

    mutating func run(_ arguments: [String]) async -> Int32 {
        // The driver's options, wherever they come, up to a lone --, after
        // which everything is the app's own.
        var rest: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if argument == "--" {
                rest += arguments[(index - 1)...]
                break
            }
            switch argument {
            case "--json": printsJSON = true
            case "--brief": brief = true
            case "--help": print(Self.usage); return 0
            case "--port", "--device", "--timeout":
                guard index < arguments.count else { return fail("\(argument) needs a value.") }
                let value = arguments[index]
                index += 1
                switch argument {
                case "--port":
                    guard let number = Int(value) else { return fail("--port is a number.") }
                    port = number
                case "--device": device = value
                default:
                    guard let seconds = Double(value) else { return fail("--timeout is a number of seconds.") }
                    timeout = seconds
                }
            case "--script", "--into", "--replace":
                rest.append(argument)
            default:
                if argument.hasPrefix("--") { return fail("Unknown option \(argument).\n\n\(Self.usage)") }
                rest.append(argument)
            }
        }
        guard let command = rest.first else {
            print(Self.usage)
            return 64
        }
        rest.removeFirst()
        do {
            switch command {
            case "help", "-h": print(Self.usage); return 0
            case "launch": return try await launch(rest)
            case "screenshot": return try screenshot(rest.first)
            case "install-skill": return try installSkill(rest)
            case "targets": return try await targets()
            case "smoke": return try await smoke()
            case "state": return try printAnswer(await get("/state"))
            case "commands": return try printAnswer(await get("/help"))
            case "trace": return try await trace(rest)
            case "send":
                guard let text = rest.first, let body = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                else { return fail("send needs a command's JSON, as '{\"command\": \"targets\"}'.") }
                return try printAnswer(await post(json))
            default:
                return try printAnswer(await post(try commandJSON(command, rest)))
            }
        } catch {
            return fail("\(error)")
        }
    }

    // MARK: Commands

    /// A gesture command's JSON: its name, its target if the first argument
    /// isn't key=value, and each key=value, as text the app reads leniently,
    /// or as JSON where it starts with { or [.
    func commandJSON(_ command: String, _ arguments: [String]) throws -> [String: Any] {
        var json: [String: Any] = ["command": command]
        var rest = arguments
        if let first = rest.first, !first.contains("=") {
            json["target"] = first
            rest.removeFirst()
        }
        for argument in rest {
            guard let equals = argument.firstIndex(of: "=") else {
                throw DriveError("\(argument) isn't key=value.")
            }
            let key = String(argument[..<equals])
            let value = String(argument[argument.index(after: equals)...])
            if value.hasPrefix("{") || value.hasPrefix("["),
               let parsed = try? JSONSerialization.jsonObject(with: Data(value.utf8)) {
                json[key] = parsed
            } else {
                json[key] = value
            }
        }
        return json
    }

    func targets() async throws -> Int32 {
        let answer = try await get("/targets")
        if printsJSON { return try printAnswer(answer) }
        guard let result = answer["result"] as? [String: Any] else { return try printAnswer(answer) }
        var rows: [[String]] = [["KIND", "ID", "DEFAULT", "DETAIL"]]
        let kinds: [(key: String, kind: String)] = [
            ("grids", "grid"), ("items", "item"), ("surfaces", "surface"), ("tabs", "tab"), ("handles", "handle"), ("panels", "panel"),
        ]
        for (key, kind) in kinds {
            for target in result[key] as? [[String: Any]] ?? [] {
                rows.append([kind, "\(target["id"] ?? "?")", "\(target["default"] ?? "")", detail(of: kind, target)])
            }
        }
        print(table(rows))
        if answer["outcome"] as? String != "ready" { print("(the app is still settling)") }
        return 0
    }

    private func detail(of kind: String, _ target: [String: Any]) -> String {
        switch kind {
        case "grid":
            let offset = (target["offset"] as? [Any])?.last.map { "\($0)" } ?? "?"
            return "scrolled \(offset) of \(target["maxOffset"] ?? "?") pt"
        case "item":
            return (target["appID"] as? String).map { "app id \($0)" } ?? ""
        case "handle":
            let carries = (target["carries"] as? String).map { "carries \($0)" } ?? "carries what its app finds"
            return target["enabled"] as? Bool == false ? carries + ", off" : carries
        case "panel":
            return "at " + vectorText(target["at"])
        default:
            return (target["busy"] as? Bool) == true ? "busy" : ""
        }
    }

    /// A vector as a person reads it: "(0.00, 1.36, -0.66) m".
    private func vectorText(_ value: Any?) -> String {
        guard let parts = value as? [NSNumber], parts.count == 3 else { return "?" }
        return String(format: "(%.2f, %.2f, %.2f) m", parts[0].doubleValue, parts[1].doubleValue, parts[2].doubleValue)
    }

    func smoke() async throws -> Int32 {
        let answer = try await post(["command": "smoke"])
        if printsJSON { _ = try printAnswer(answer) }
        guard answer["ok"] as? Bool == true, let result = answer["result"] as? [String: Any] else {
            return try printsJSON ? 1 : printAnswer(answer)
        }
        if !printsJSON {
            for drive in result["drives"] as? [[String: Any]] ?? [] {
                let passed = drive["passed"] as? Bool == true
                let command = (drive["command"] as? [String: Any])?["command"] ?? "?"
                var line = "\(passed ? "PASS" : "FAIL")  \(drive["kind"] ?? "?") \(drive["id"] ?? "?"): \(command)"
                if let outcome = drive["outcome"] { line += " → \(outcome)" }
                if let expected = drive["expected"] as? [Any] { line += " (expected \(expected.map { "\($0)" }.joined(separator: " or ")))" }
                if let error = drive["error"] { line += ": \(error)" }
                print(line)
            }
            print("\(result["passed"] ?? 0) passed, \(result["failed"] ?? 0) failed")
        }
        return (result["failed"] as? Int ?? 1) == 0 ? 0 : 1
    }

    func trace(_ arguments: [String]) async throws -> Int32 {
        let answer = try await post(try commandJSON("trace", arguments))
        if printsJSON { return try printAnswer(answer) }
        let interactions = (answer["result"] as? [String: Any])?["interactions"] as? [[String: Any]] ?? []
        if interactions.isEmpty { print("No interactions traced.") }
        for interaction in interactions {
            print(interaction["summary"] ?? "?")
        }
        return answer["ok"] as? Bool == true ? 0 : 1
    }

    // MARK: The skill

    /// The verification skill this package ships for apps on GestureKit, in
    /// the checkout this tool was built from: `swift run` builds it there,
    /// from this file, three folders below the package's root.
    static let shippedSkill = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".agents/skills/verify-gestures", isDirectory: true)

    /// Copies the `verify-gestures` skill into `--into`'s folder, the
    /// current folder's `.agents/skills` unless given, as
    /// `<folder>/verify-gestures`, refusing to replace one already there
    /// unless `--replace`, so an adopter's agents inherit how to drive and
    /// prove its gestures with this tool.
    func installSkill(_ arguments: [String]) throws -> Int32 {
        var folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".agents/skills", isDirectory: true)
        var replaces = false
        var rest = arguments
        while let next = rest.first {
            rest.removeFirst()
            switch next {
            case "--into":
                guard let path = rest.first else { throw DriveError("--into needs a folder, as --into .agents/skills.") }
                rest.removeFirst()
                folder = URL(fileURLWithPath: path, isDirectory: true)
            case "--replace":
                replaces = true
            default:
                throw DriveError("install-skill takes --into FOLDER and --replace; not \(next).")
            }
        }
        let files = FileManager.default
        let source = Self.shippedSkill
        guard files.fileExists(atPath: source.appendingPathComponent("SKILL.md").path) else {
            throw DriveError("The skill isn't beside this tool's sources, at \(source.path); run gesturekit-drive from a checkout of GestureKit.")
        }
        let destination = folder.appendingPathComponent("verify-gestures", isDirectory: true)
        if files.fileExists(atPath: destination.path) {
            guard replaces else {
                throw DriveError("\(destination.path) is there already; add --replace to replace it with GestureKit's.")
            }
            try files.removeItem(at: destination)
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try files.copyItem(at: source, to: destination)
        let copied = files.enumerator(atPath: destination.path)?.compactMap { $0 as? String }
            .filter { !$0.hasPrefix(".") && !$0.contains("/.") }
            .filter { path in
                var isFolder: ObjCBool = false
                return files.fileExists(atPath: destination.appendingPathComponent(path).path, isDirectory: &isFolder) && !isFolder.boolValue
            }
            .sorted() ?? []
        print("Installed GestureKit's verify-gestures skill in \(destination.path):")
        for path in copied { print("  \(path)") }
        let claudeSkills = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".claude/skills")
        if folder.standardizedFileURL.path.hasSuffix("/.agents/skills"), !files.fileExists(atPath: claudeSkills.path) {
            print("Claude Code reads .claude/skills; to share these, link it: mkdir -p .claude && ln -s ../.agents/skills .claude/skills")
        }
        print("Its SKILL.md says how to launch your app, check, drive, capture, and clean up; add /artifacts to your .gitignore.")
        return 0
    }

    // MARK: The simulator

    func launch(_ arguments: [String]) async throws -> Int32 {
        var rest = arguments
        guard let bundle = rest.first, !bundle.hasPrefix("-") else {
            throw DriveError("launch needs the app's bundle id, as launch com.example.app.")
        }
        rest.removeFirst()
        var script: String?
        var appArguments: [String] = []
        while let next = rest.first {
            rest.removeFirst()
            if next == "--script", let file = rest.first {
                script = file
                rest.removeFirst()
            } else if next == "--" {
                appArguments = rest
                rest = []
            } else {
                throw DriveError("launch takes --script FILE, then -- and the app's own arguments; not \(next).")
            }
        }
        _ = try? simctl(["terminate", device, bundle])
        var environment = ["SIMCTL_CHILD_GESTUREKIT_AUTOMATION_PORT": "\(port)"]
        var resultsURL: URL?
        if let script {
            let container = try simctl(["get_app_container", device, bundle, "data"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = URL(fileURLWithPath: container).appendingPathComponent("tmp/gesturekit-automation-script.json")
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: script), to: destination)
            let results = URL(fileURLWithPath: destination.path + ".results.json")
            try? FileManager.default.removeItem(at: results)
            resultsURL = results
            environment["SIMCTL_CHILD_GESTUREKIT_AUTOMATION_SCRIPT"] = destination.path
        }
        environment["SIMCTL_CHILD_GESTUREKIT_AUTOMATION"] = "1"
        _ = try simctl(["launch", device, bundle] + appArguments, environment: environment)
        let deadline = Date.now.addingTimeInterval(timeout)
        if let resultsURL {
            while !FileManager.default.fileExists(atPath: resultsURL.path) {
                guard Date.now < deadline else { throw DriveError("The script's results never came, after \(Int(timeout)) s.") }
                try await Task.sleep(for: .milliseconds(500))
            }
            let data = try Data(contentsOf: resultsURL)
            print(String(decoding: data, as: UTF8.self))
            let results = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (results?["failed"] as? Int ?? 1) == 0 ? 0 : 1
        }
        while true {
            if let state = try? await get("/state"), (state["result"] as? [String: Any])?["ready"] as? Bool == true {
                print("\(bundle) is ready on 127.0.0.1:\(port)")
                return 0
            }
            guard Date.now < deadline else {
                throw DriveError("\(bundle) never answered on 127.0.0.1:\(port) as ready, after \(Int(timeout)) s. Is it a debug build on GestureKit, showing an adapter?")
            }
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    func screenshot(_ file: String?) throws -> Int32 {
        let path = file ?? "gesturekit-\(Int(Date.now.timeIntervalSince1970)).png"
        _ = try simctl(["io", device, "screenshot", path])
        print(path)
        return 0
    }

    /// Runs `xcrun simctl` with `arguments`, and gives what it printed.
    @discardableResult
    func simctl(_ arguments: [String], environment: [String: String] = [:]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        var merged = ProcessInfo.processInfo.environment
        for (key, value) in environment { merged[key] = value }
        process.environment = merged
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        let complained = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DriveError("simctl \(arguments.joined(separator: " ")) failed: \(String(decoding: complained, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return String(decoding: printed, as: UTF8.self)
    }

    // MARK: The app's server

    func get(_ path: String) async throws -> [String: Any] {
        try await request(path, body: nil)
    }

    func post(_ json: [String: Any]) async throws -> [String: Any] {
        try await request("/", body: try JSONSerialization.data(withJSONObject: json))
    }

    /// The app's answer, as JSON, with the bytes it came in, which keep its
    /// numbers as the app wrote them.
    private func request(_ path: String, body: Data?) async throws -> [String: Any] {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { throw DriveError("No URL for port \(port).") }
        var request = URLRequest(url: url)
        request.timeoutInterval = max(timeout, 600)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw DriveError("Nothing answered on 127.0.0.1:\(port): launch the app with its automation on first (gesturekit-drive launch <bundle-id>).")
        }
        guard var answer = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DriveError("The app's answer isn't a JSON object.")
        }
        answer[Self.bytesKey] = data
        return answer
    }

    /// Where an answer keeps the bytes it came in.
    static let bytesKey = "__bytes"

    /// Prints `answer`, whole, or, `brief`, its outcome and result; 0 if it
    /// was ok.
    func printAnswer(_ answer: [String: Any]) throws -> Int32 {
        if !brief || answer["ok"] as? Bool != true, let bytes = answer[Self.bytesKey] as? Data {
            print(String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .newlines))
        } else {
            let shown: [String: Any] = ["ok": true, "outcome": answer["outcome"] ?? NSNull(), "result": answer["result"] ?? NSNull()]
            print(Self.render(shown))
        }
        return answer["ok"] as? Bool == false ? 1 : 0
    }

    /// `value` as pretty JSON, keys sorted, each number in its shortest
    /// form, as the app wrote it, rather than to seventeen digits.
    static func render(_ value: Any, indent: String = "") -> String {
        let inner = indent + "  "
        switch value {
        case let object as [String: Any]:
            guard !object.isEmpty else { return "{}" }
            let members = object.keys.sorted().map { "\(inner)\(render($0)) : \(render(object[$0] ?? NSNull(), indent: inner))" }
            return "{\n" + members.joined(separator: ",\n") + "\n\(indent)}"
        case let array as [Any]:
            guard !array.isEmpty else { return "[]" }
            return "[\n" + array.map { inner + render($0, indent: inner) }.joined(separator: ",\n") + "\n\(indent)]"
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return number.boolValue ? "true" : "false"
        case let number as NSNumber:
            let double = number.doubleValue
            return double.rounded() == double && abs(double) < 1e15 ? "\(Int64(double))" : "\(double)"
        case let string as String:
            let data = (try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        default:
            return "null"
        }
    }

    private func table(_ rows: [[String]]) -> String {
        let widths = (0..<(rows.first?.count ?? 0)).map { column in rows.map { $0[column].count }.max() ?? 0 }
        return rows.map { row in
            row.enumerated().map { column, cell in
                column == row.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }

    private func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("gesturekit-drive: \(message)\n".utf8))
        return 1
    }
}
#else
@main
struct GestureKitDrive {
    static func main() {
        print("gesturekit-drive runs on a Mac, driving an app in a visionOS simulator.")
    }
}
#endif
