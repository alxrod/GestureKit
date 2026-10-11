import Foundation

/// Which GestureKit commit a copy of one of its skills came from, written
/// into the copy's `SKILL.md` as `gesturekit-drive install-skill` makes it,
/// so the copy can be told apart from the GestureKit an app pins later.
///
/// The stamp goes in the frontmatter's `metadata`, which the Agent Skills
/// format (agentskills.io) defines as a map of strings to strings for a
/// client's own properties, so the stamped skill stays a valid one:
///
///     ---
///     name: verify-gestures
///     description: …
///     metadata:
///       gesturekit-revision: "409d7e2…"
///     ---
///
/// Three readers know this shape: this type, the skill's own
/// `scripts/gesture-verify.sh doctor`, and the Claude Code plugin's
/// `scripts/pinned-skill.sh`. Change it in all three.
public enum SkillStamp {
    /// The key under `metadata` that names the revision.
    public static let metadataKey = "gesturekit-revision"

    /// Something about a `SKILL.md` that keeps it from being stamped.
    public enum Problem: Error, Equatable, CustomStringConvertible {
        /// The text doesn't open with a `---` line, or never closes it.
        case noFrontmatter
        /// `metadata` is written inline, as `metadata: {…}`, which the
        /// stamp doesn't rewrite.
        case inlineMetadata
        /// The revision isn't a full commit id: 40 or 64 lowercase hex
        /// digits.
        case notARevision(String)

        public var description: String {
            switch self {
            case .noFrontmatter: "its SKILL.md has no frontmatter between --- lines"
            case .inlineMetadata: "its SKILL.md's metadata is written inline, which the stamp doesn't rewrite"
            case .notARevision(let text): "\(text) isn't a full commit id"
            }
        }
    }

    /// The revision `skill`, a `SKILL.md`'s text, was stamped with, or nil
    /// when it carries no stamp, as GestureKit's own copy doesn't.
    public static func revision(in skill: String) -> String? {
        guard let frontmatter = Frontmatter(skill), let block = frontmatter.metadataBlock(),
              let line = block.keyLine
        else { return nil }
        let value = Self.value(ofLine: frontmatter.lines[line])
        return value.isEmpty ? nil : value
    }

    /// `skill`, a `SKILL.md`'s text, with its frontmatter's `metadata`
    /// naming `revision`, or, given nil, naming none, everything else as it
    /// was: an existing stamp is replaced, and a `metadata` left empty goes.
    public static func stamping(_ skill: String, with revision: String?) throws(Problem) -> String {
        if let revision, !isRevision(revision) { throw .notARevision(revision) }
        guard var frontmatter = Frontmatter(skill) else { throw .noFrontmatter }
        let entry = revision.map { "\(metadataKey): \"\($0)\"" }
        if let metadata = frontmatter.metadataLine {
            guard frontmatter.lines[metadata].trimmingCharacters(in: .whitespaces) == "metadata:" else {
                throw .inlineMetadata
            }
            let block = frontmatter.metadataBlock() ?? Frontmatter.MetadataBlock(entries: [], keyLine: nil, indent: "  ")
            switch (block.keyLine, entry) {
            case (let line?, let entry?):
                frontmatter.lines[line] = block.indent + entry
            case (let line?, nil):
                frontmatter.lines.remove(at: line)
                if block.entries.count == 1 { frontmatter.lines.remove(at: metadata) }
            case (nil, let entry?):
                frontmatter.lines.insert(block.indent + entry, at: (block.entries.last ?? metadata) + 1)
            case (nil, nil):
                break
            }
        } else if let entry {
            frontmatter.lines.insert(contentsOf: ["metadata:", "  " + entry], at: frontmatter.closing)
        }
        return frontmatter.lines.joined(separator: "\n")
    }

    /// Whether `text` is a full commit id, SHA-1's 40 lowercase hex digits
    /// or SHA-256's 64, as `git rev-parse HEAD` prints one.
    public static func isRevision(_ text: String) -> Bool {
        (text.count == 40 || text.count == 64) && text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// A `key: value` line's value, its quotes taken off, or an unquoted
    /// one's trailing comment.
    private static func value(ofLine line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if let quote = value.first, quote == "\"" || quote == "'" {
            value.removeFirst()
            if let close = value.firstIndex(of: quote) { value = String(value[..<close]) }
        } else if let comment = value.range(of: " #") {
            value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return value
    }
}

/// A `SKILL.md`'s lines, with where its frontmatter closes and where its
/// `metadata` key is.
private struct Frontmatter {
    var lines: [String]
    /// The index of the closing `---` line.
    var closing: Int

    init?(_ text: String) {
        lines = text.components(separatedBy: "\n")
        guard lines.first.map(Self.isDelimiter) == true,
              let close = lines.dropFirst().firstIndex(where: Self.isDelimiter)
        else { return nil }
        closing = close
    }

    private static func isDelimiter(_ line: String) -> Bool {
        line.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r")) == "---"
    }

    /// The `metadata:` line, at the frontmatter's top level.
    var metadataLine: Int? {
        (1..<closing).first { lines[$0].hasPrefix("metadata:") }
    }

    struct MetadataBlock {
        /// The lines of its entries, indented under `metadata:`.
        var entries: [Int]
        /// The line of the stamp's key among them.
        var keyLine: Int?
        /// Its entries' indentation, or two spaces.
        var indent: String
    }

    /// The indented lines under `metadata:`, up to the next top-level key.
    func metadataBlock() -> MetadataBlock? {
        guard let metadata = metadataLine else { return nil }
        var entries: [Int] = []
        var index = metadata + 1
        while index < closing, let first = lines[index].first, first == " " || first == "\t" {
            entries.append(index)
            index += 1
        }
        let keyLine = entries.first {
            lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix(SkillStamp.metadataKey + ":")
        }
        let indent = entries.first.map { String(lines[$0].prefix { $0 == " " || $0 == "\t" }) } ?? "  "
        return MetadataBlock(entries: entries, keyLine: keyLine, indent: indent)
    }
}
