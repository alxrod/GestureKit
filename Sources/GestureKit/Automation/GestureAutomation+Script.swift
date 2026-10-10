#if os(visionOS) && DEBUG
import GestureCore
import Foundation

extension GestureAutomation {
    /// Runs the commands in the JSON file at `url`, as the launch asks with
    /// `-GestureKitAutomationScript <file>`, a list of them or
    /// `{"commands": [...]}`, in order, once the app has settled, and writes
    /// their answers beside it, `<file>.results.json`: whether it finished,
    /// how many failed, and each answer, as the server would have given it.
    /// Each command is logged at info as it ends ("Automation: pluck →
    /// spawned"), then the run ("Automation script finished: 6 commands, 0
    /// failed"). A file it can't read is said in the results, as is a
    /// command that fails, and the rest go on.
    func runScript(at url: URL) {
        let resultsURL = URL(fileURLWithPath: url.path + ".results.json")
        Task { @MainActor in
            await settle(atMost: 30)
            let commands: [AutomationJSON]
            do {
                let json = try AutomationJSON.decoded(from: Data(contentsOf: url))
                commands = json.array ?? json["commands"]?.array ?? [json]
            } catch {
                Self.write(["finished": true, "commands": 0, "failed": 1, "error": .string("Couldn't read the script at \(url.path): \(error)")], to: resultsURL)
                gestureAutomationLogger.error("Automation script: couldn't read \(url.path)")
                return
            }
            var results: [AutomationJSON] = []
            for command in commands {
                results.append(await perform(command))
            }
            let failed = results.filter { $0["ok"] != true }.count
            Self.write([
                "finished": true,
                "commands": .number(Double(commands.count)),
                "failed": .number(Double(failed)),
                "results": .array(results),
            ], to: resultsURL)
            gestureAutomationLogger.info("Automation script finished: \(commands.count, privacy: .public) commands, \(failed, privacy: .public) failed, its results at \(resultsURL.path)")
        }
    }

    private static func write(_ json: AutomationJSON, to url: URL) {
        do {
            try json.encoded(pretty: true).write(to: url, options: .atomic)
        } catch {
            gestureAutomationLogger.error("Automation script: couldn't write its results to \(url.path): \(String(describing: error))")
        }
    }
}
#endif
