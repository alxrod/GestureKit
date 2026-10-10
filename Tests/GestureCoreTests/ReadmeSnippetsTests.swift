import Foundation
import Testing

/// The README's Swift is code the lab compiles, so it can't drift from the
/// API: each Swift block in `README.md` is exactly the text of a file in
/// `Lab/GestureLab/ReadmeSnippets/`, after the file's leading comment, which
/// `scripts/build-check.sh` compiles with GestureLab; and each of those files
/// is shown. A block that can't be compiled there, as a package manifest,
/// says so on the line before its fence: `<!-- Not compiled: … -->`.
///
/// To change a snippet, change its file, build the lab, and put the file's
/// text in the README's block.
@Suite struct ReadmeSnippetsTests {
    @Test("The snippets are there to compare with")
    func snippetsAreThere() throws {
        #expect(try readmeSnippets().count >= 10)
        #expect(try readmeSwiftBlocks().filter(\.isCompiled).count >= 10)
    }

    @Test("Each Swift block in the README is a snippet the lab compiles")
    func blocksAreSnippets() throws {
        let snippets = Set(try readmeSnippets().values)
        for block in try readmeSwiftBlocks() where block.isCompiled {
            #expect(
                snippets.contains(block.code),
                "The README's block at line \(block.line) isn't the text of any file in Lab/GestureLab/ReadmeSnippets/"
            )
        }
    }

    @Test("Each snippet the lab compiles is in the README")
    func snippetsAreShown() throws {
        let blocks = Set(try readmeSwiftBlocks().map(\.code))
        for (file, snippet) in try readmeSnippets() {
            #expect(blocks.contains(snippet), "The README doesn't show \(file) as it is")
        }
    }
}

/// The repository's root: this file is `Tests/GestureCoreTests/` in it.
private let readmeRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

/// A Swift block of the README: its code, the line its fence opens on,
/// counting from 1, and whether it's compiled, which the line before the
/// fence says it isn't.
private struct ReadmeSwiftBlock {
    var code: String
    var line: Int
    var isCompiled: Bool
}

/// The README's Swift blocks, in order.
private func readmeSwiftBlocks() throws -> [ReadmeSwiftBlock] {
    let text = try String(contentsOf: readmeRepositoryRoot.appending(path: "README.md"), encoding: .utf8)
    let lines = text.components(separatedBy: "\n")
    var blocks: [ReadmeSwiftBlock] = []
    var index = 0
    while index < lines.count {
        guard lines[index] == "```swift" else {
            index += 1
            continue
        }
        let opened = index
        var code: [String] = []
        index += 1
        while index < lines.count, lines[index] != "```" {
            code.append(lines[index])
            index += 1
        }
        let notCompiled = opened > 0 && lines[opened - 1].hasPrefix("<!-- Not compiled")
        blocks.append(ReadmeSwiftBlock(code: code.joined(separator: "\n"), line: opened + 1, isCompiled: !notCompiled))
        index += 1
    }
    return blocks
}

/// Each snippet file's code, by its name: its text after its leading comment
/// lines and the blank lines after them, without its last newline.
private func readmeSnippets() throws -> [String: String] {
    let folder = readmeRepositoryRoot.appending(path: "Lab/GestureLab/ReadmeSnippets")
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        .filter { $0.hasSuffix(".swift") }
    var snippets: [String: String] = [:]
    for name in names {
        let text = try String(contentsOf: folder.appending(path: name), encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, first.hasPrefix("//") || first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        snippets[name] = lines.joined(separator: "\n")
    }
    return snippets
}
