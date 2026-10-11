import Foundation
import Testing

/// The agent skills in `.agents/skills/` keep the shape their harnesses and
/// their readers count on: each skill's `SKILL.md` opens with frontmatter
/// naming it as its folder is named, with a description, so it registers;
/// each helper it ships is executable; `.claude/skills` is a link to the
/// folder, so Claude Code finds the same skills; and each feature map's
/// index lists exactly the files beside it, each an H1, a paragraph, and the
/// four sections the map's contract names, in order.
@Suite struct AgentSkillsTests {
    @Test("Each skill's SKILL.md names it as its folder does, with a description")
    func skillsRegister() throws {
        let skills = try skillFolders()
        #expect(skills.contains("verify-gesturelab"))
        #expect(skills.contains("verify-gestures"))
        for skill in skills {
            let text = try String(contentsOf: skillsRoot.appending(path: "\(skill)/SKILL.md"), encoding: .utf8)
            let lines = text.components(separatedBy: "\n")
            #expect(lines.first == "---", "\(skill)/SKILL.md doesn't open with frontmatter")
            let closing = lines.dropFirst().firstIndex(of: "---")
            #expect(closing != nil, "\(skill)/SKILL.md's frontmatter never closes")
            let frontmatter = lines[1..<(closing ?? 1)]
            #expect(frontmatter.contains("name: \(skill)"), "\(skill)/SKILL.md isn't named \(skill)")
            let description = frontmatter.first { $0.hasPrefix("description: ") }
            #expect((description?.count ?? 0) > 80, "\(skill)/SKILL.md has no description saying when to reach for it")
        }
    }

    @Test("Each skill's helpers are executable")
    func helpersRun() throws {
        let files = FileManager.default
        for skill in try skillFolders() {
            let scripts = skillsRoot.appending(path: "\(skill)/scripts")
            guard let names = try? files.contentsOfDirectory(atPath: scripts.path(percentEncoded: false)) else { continue }
            for name in names where !name.hasPrefix(".") {
                #expect(files.isExecutableFile(atPath: scripts.appending(path: name).path(percentEncoded: false)), "\(skill)/scripts/\(name) isn't executable")
            }
        }
    }

    @Test(".claude/skills is a link to .agents/skills")
    func claudeFindsTheSkills() throws {
        let link = repositoryRoot.appending(path: ".claude/skills").path(percentEncoded: false)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link) == "../.agents/skills")
    }

    @Test("Each feature map's index lists exactly the feature files beside it")
    func indexesMatchTheirFiles() throws {
        for features in try featureMaps() {
            let readme = try String(contentsOf: features.appending(path: "README.md"), encoding: .utf8)
            let listed = Set(markdownLinks(in: readme).filter { $0.hasPrefix("./") && $0.hasSuffix(".md") }.map { String($0.dropFirst(2)) })
            let files = Set(try featureFiles(in: features))
            #expect(listed == files, "\(features.lastPathComponent)/README.md lists \(listed.sorted()), beside \(files.sorted())")
        }
    }

    @Test("Each feature file is an H1, a paragraph, and the contract's four sections in order")
    func featuresKeepTheContract() throws {
        let sections = ["Sub-features", "How to get to it (user POV)", "Driving it with gesturekit-drive", "Gotchas"]
        var checked = 0
        for features in try featureMaps() {
            for name in try featureFiles(in: features) {
                let text = try String(contentsOf: features.appending(path: name), encoding: .utf8)
                let lines = text.components(separatedBy: "\n")
                #expect(lines.first?.hasPrefix("# ") == true, "\(name) doesn't open with an H1")
                let firstSection = lines.firstIndex { $0.hasPrefix("## ") } ?? lines.count
                let paragraph = lines[1..<firstSection].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                #expect(!paragraph.isEmpty, "\(name) has no paragraph before its sections")
                let headings = lines.filter { $0.hasPrefix("## ") }.map { String($0.dropFirst(3)) }
                #expect(headings == sections, "\(name)'s sections are \(headings)")
                let subFeatures = section("Sub-features", of: lines).filter { $0.hasPrefix("- `") }
                #expect(!subFeatures.isEmpty, "\(name) lists no sub-features")
                let driving = section("Driving it with gesturekit-drive", of: lines)
                #expect(driving.first { !$0.isEmpty } == "Preconditions:", "\(name)'s recipes don't start with Preconditions:")
                #expect(driving.contains { $0.hasPrefix("- **") && $0.contains("Run `") }, "\(name) has no recipe with a command")
                checked += 1
            }
        }
        #expect(checked >= 8)
    }
}

/// The repository's root: this file is `Tests/GestureCoreTests/` in it.
private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let skillsRoot = repositoryRoot.appending(path: ".agents/skills")

/// The skills, by their folders' names.
private func skillFolders() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: skillsRoot.path(percentEncoded: false))
        .filter { !$0.hasPrefix(".") }
        .sorted()
}

/// Each skill's feature map, its `features/` folder, where it has one.
private func featureMaps() throws -> [URL] {
    try skillFolders()
        .map { skillsRoot.appending(path: "\($0)/features") }
        .filter { FileManager.default.fileExists(atPath: $0.appending(path: "README.md").path(percentEncoded: false)) }
}

/// A feature map's files, but its index.
private func featureFiles(in features: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: features.path(percentEncoded: false))
        .filter { $0.hasSuffix(".md") && $0 != "README.md" }
        .sorted()
}

/// The targets of a Markdown text's inline links.
private func markdownLinks(in text: String) -> [String] {
    var links: [String] = []
    var rest = text[...]
    while let open = rest.range(of: "](") {
        let after = rest[open.upperBound...]
        guard let close = after.firstIndex(of: ")") else { break }
        links.append(String(after[..<close]))
        rest = after[close...]
    }
    return links
}

/// The lines of the H2 section titled `title`, up to the next.
private func section(_ title: String, of lines: [String]) -> [String] {
    guard let start = lines.firstIndex(of: "## \(title)") else { return [] }
    let body = lines[(start + 1)...]
    let end = body.firstIndex { $0.hasPrefix("## ") } ?? lines.count
    return Array(lines[(start + 1)..<end])
}
