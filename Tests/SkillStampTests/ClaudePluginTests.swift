import Foundation
import Testing
@testable import SkillStamp

/// The Claude Code marketplace at the repository's root and its one plugin
/// keep the shape Claude Code's documentation gives them
/// (code.claude.com/docs/en/plugins/marketplace-reference and
/// /plugins-reference; `claude plugin validate` is the authority), and the
/// plugin's stub skill stays in step with the skill it loads and the stamp
/// it reads.
@Suite struct ClaudePluginTests {
    @Test("The marketplace names its owner and lists the plugin by a relative path inside the repository")
    func marketplaceListsThePlugin() throws {
        let marketplace = try json(at: ".claude-plugin/marketplace.json")
        let name = try #require(marketplace["name"] as? String)
        #expect(isPluginID(name), "\(name) isn't a marketplace name Claude Code installs from")
        let owner = marketplace["owner"] as? [String: Any]
        #expect((owner?["name"] as? String)?.isEmpty == false, "the marketplace names no owner")
        #expect(!((marketplace["description"] as? String) ?? "").isEmpty)
        let plugins = try #require(marketplace["plugins"] as? [[String: Any]])
        #expect(plugins.count == 1)
        for entry in plugins {
            let entryName = try #require(entry["name"] as? String)
            #expect(isPluginID(entryName))
            let source = try #require(entry["source"] as? String)
            #expect(source.hasPrefix("./") && !source.contains(".."), "\(source) isn't a relative path inside the marketplace")
            let manifest = try json(at: String(source.dropFirst(2)) + "/.claude-plugin/plugin.json")
            #expect(manifest["name"] as? String == entryName, "the entry and the plugin's manifest name it differently")
        }
    }

    @Test("The plugin's manifest is kebab-case, sets no version so each commit is an update, and its paths are its own")
    func manifestKeepsItsShape() throws {
        let manifest = try json(at: "plugins/gesturekit/.claude-plugin/plugin.json")
        let name = try #require(manifest["name"] as? String)
        #expect(name.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil, "\(name) isn't kebab-case")
        #expect(!name.hasPrefix("claude") && !name.hasPrefix("anthropic"), "\(name) is a name Claude Code reserves")
        #expect(manifest["version"] == nil, "a version keeps users on it until it changes; the stub reads the app's pin, so every commit should update")
        #expect(((manifest["author"] as? [String: Any])?["name"] as? String)?.isEmpty == false)
        #expect(manifest["license"] as? String == "MIT")
        let known: Set = ["name", "displayName", "description", "author", "homepage", "repository", "license", "keywords"]
        #expect(Set(manifest.keys).isSubset(of: known), "unexpected keys: \(Set(manifest.keys).subtracting(known).sorted())")
    }

    @Test("The stub skill is named as its folder is, says what the package's skill says, and approves the one command it runs")
    func stubLoadsThePinnedSkill() throws {
        let stub = try text(at: "plugins/gesturekit/skills/verify-gestures/SKILL.md")
        let shipped = try text(at: ".agents/skills/verify-gestures/SKILL.md")
        let frontmatter = try #require(frontmatterLines(of: stub))
        #expect(frontmatter.contains("name: verify-gestures"))
        let description = frontmatter.first { $0.hasPrefix("description: ") }
        #expect(description != nil && description == frontmatterLines(of: shipped)?.first { $0.hasPrefix("description: ") },
                "the stub's description isn't the package skill's, so the two would be reached for differently")
        #expect((description?.count ?? 0) <= 1_024 + "description: ".count)

        let script = "${CLAUDE_PLUGIN_ROOT}/scripts/pinned-skill.sh"
        #expect(frontmatter.contains("allowed-tools: Bash(\(script) *)"), "allowed-tools doesn't approve the locator, so its injection would abort the skill")
        let injections = stub.components(separatedBy: "\n").filter { $0.hasPrefix("!`") }
        #expect(injections.count == 1)
        #expect(injections.first?.hasPrefix("!`\(script) ") == true && injections.first?.hasSuffix("`") == true,
                "the injected command isn't the approved locator: \(injections)")
        #expect(FileManager.default.isExecutableFile(atPath: root.appending(path: "plugins/gesturekit/scripts/pinned-skill.sh").path(percentEncoded: false)))
    }

    @Test("The locator and the skill's doctor read the stamp SkillStamp writes, in the folder it names")
    func readersShareTheStamp() throws {
        let locator = try text(at: "plugins/gesturekit/scripts/pinned-skill.sh")
        let helper = try text(at: ".agents/skills/verify-gestures/scripts/gesture-verify.sh")
        for (name, script) in [("pinned-skill.sh", locator), ("gesture-verify.sh", helper)] {
            #expect(script.contains("/^[ \\t]+\(SkillStamp.metadataKey):/"), "\(name) doesn't read the \(SkillStamp.metadataKey) stamp")
            #expect(script.contains("/^metadata:[ \\t\\r]*$/"), "\(name) doesn't look for the stamp under metadata")
        }
        #expect(locator.contains("skill_folder=\(InstalledSkill.relativeFolder)\n"))
    }
}

/// The repository's root: this file is `Tests/SkillStampTests/` in it.
private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func text(at path: String) throws -> String {
    try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

private func json(at path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appending(path: path))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], "\(path) isn't a JSON object")
}

/// A name Claude Code installs from: letters, digits, `.`, `_`, and `-`,
/// starting with a letter or digit, without `..`.
private func isPluginID(_ name: String) -> Bool {
    name.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil && !name.contains("..")
}

/// A SKILL.md's frontmatter lines, between its `---` lines.
private func frontmatterLines(of text: String) -> [String]? {
    let lines = text.components(separatedBy: "\n")
    guard lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") else { return nil }
    return Array(lines[1..<close])
}
