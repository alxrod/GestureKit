import Foundation

/// The GestureKit revision a checkout's copy of a skill would be stamped
/// with, read from what git says of the checkout: a revision only where git
/// can vouch for the skill's bytes, so a stamp is never a guess.
public enum CheckoutRevision: Equatable, Sendable {
    /// The checkout's commit, whose skill is the one on disk.
    case known(String)
    /// Git can't say, and why, in words that finish "wrote no stamp: …".
    case unknown(String)

    /// The revision of the GestureKit checkout at `packageRoot`, from what
    /// git printed there: `topLevel`, `git rev-parse --show-toplevel`;
    /// `head`, `git rev-parse HEAD`; and `skillChanges`, `git status
    /// --porcelain` of the skill's folder. Each is nil where git failed.
    /// Paths are compared as given, so resolve their links first.
    public static func reading(packageRoot: String, topLevel: String?, head: String?, skillChanges: String?) -> CheckoutRevision {
        guard let topLevel = topLevel?.trimmingCharacters(in: .whitespacesAndNewlines), !topLevel.isEmpty else {
            return .unknown("GestureKit's folder, \(packageRoot), isn't a git checkout")
        }
        guard Self.trimmingSlashes(topLevel) == Self.trimmingSlashes(packageRoot) else {
            return .unknown("GestureKit's folder, \(packageRoot), lies inside another git repository, \(topLevel), whose commit isn't GestureKit's")
        }
        guard let head = head?.trimmingCharacters(in: .whitespacesAndNewlines), SkillStamp.isRevision(head) else {
            return .unknown("git can't say which commit GestureKit's checkout, \(packageRoot), is at")
        }
        if let skillChanges, !skillChanges.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unknown("the skill in GestureKit's checkout, \(packageRoot), has changes not committed at \(head)")
        }
        return .known(head)
    }

    /// The revision, where it's known.
    public var revision: String? {
        if case .known(let revision) = self { revision } else { nil }
    }

    private static func trimmingSlashes(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

/// An installed copy's stamp held against the revision of the
/// `gesturekit-drive` that looks at it.
public enum SkillStampComparison: Equatable, Sendable {
    /// Both name the same revision.
    case inStep(String)
    /// The copy came from another revision than the driver's.
    case outOfStep(installed: String, driver: String)
    /// The copy carries no stamp, so it can't be told.
    case unstamped
    /// The driver's own revision isn't known, so it can't be told.
    case driverUnknown(installed: String)

    public init(installed: String?, driver: String?) {
        switch (installed, driver) {
        case (let installed?, let driver?):
            self = installed.lowercased() == driver.lowercased()
                ? .inStep(driver) : .outOfStep(installed: installed, driver: driver)
        case (nil, _):
            self = .unstamped
        case (let installed?, nil):
            self = .driverUnknown(installed: installed)
        }
    }

    /// The warning `gesturekit-drive` prints, once a run, about the copy at
    /// `skill`, or nil: only a copy stamped with another revision is out of
    /// step, and the warning names both and how to bring it in step.
    public func warning(skill: String, update: String) -> String? {
        guard case .outOfStep(let installed, let driver) = self else { return nil }
        return """
            gesturekit-drive: the verify-gestures skill at \(skill) came from GestureKit \(installed), \
            but this gesturekit-drive is GestureKit \(driver); bring the skill in step with: \(update)
            """
    }
}

/// What `install-skill` does with the folder it installs into.
public enum SkillInstallPlan: Equatable, Sendable {
    /// Nothing is there: copy the skill in.
    case install
    /// Replace the copy there, which came from `from`, or carries no stamp.
    case replace(from: String?)
    /// Leave the copy there, which came from the same revision.
    case keep(String)
    /// Change nothing, and say why.
    case refuse(String)

    /// The plan for a destination that `exists` or not, holding a copy
    /// stamped `installed`, against the driver's own `revision`: `--replace`
    /// replaces whatever's there; `--update` replaces only a copy from
    /// another revision, or one with no stamp, and keeps one from the same;
    /// neither refuses to touch a copy that's there.
    public static func plan(exists: Bool, installed: String?, revision: String?, replaces: Bool, updates: Bool) -> SkillInstallPlan {
        guard exists else { return .install }
        if replaces { return .replace(from: installed) }
        guard updates else {
            return .refuse("is there already; add --update to replace it if it came from another GestureKit revision, or --replace to replace it regardless")
        }
        switch SkillStampComparison(installed: installed, driver: revision) {
        case .inStep(let revision): return .keep(revision)
        case .outOfStep(let installed, _): return .replace(from: installed)
        case .unstamped: return .replace(from: nil)
        case .driverUnknown(let installed):
            return .refuse("came from GestureKit \(installed), and this gesturekit-drive can't say which revision it is, so --update can't tell whether they differ; --replace replaces it regardless")
        }
    }
}

/// Where an app's installed copy of the skill is: the nearest
/// `.agents/skills/verify-gestures` from the working directory up to the
/// git root, the first folder holding `.git`, or the working directory
/// alone outside git.
public enum InstalledSkill {
    /// The skill's folder below a directory.
    public static let relativeFolder = ".agents/skills/verify-gestures"

    /// The directories looked in, from `start` up: through the first that
    /// `isGitRoot` says holds `.git`, or `start` alone if none up to `/`
    /// does. `start` is an absolute path.
    public static func searchedDirectories(from start: String, isGitRoot: (String) -> Bool) -> [String] {
        var directories: [String] = []
        var directory = URL(fileURLWithPath: start).standardizedFileURL.path
        while true {
            directories.append(directory)
            if isGitRoot(directory) { return directories }
            let parent = URL(fileURLWithPath: directory).deletingLastPathComponent().standardizedFileURL.path
            if parent == directory { return [directories[0]] }
            directory = parent
        }
    }

    /// The command that brings the copy in `skillsFolder` (the folder
    /// holding `verify-gestures`) in step, run from `workingDirectory`:
    /// `install-skill --update`, with `--into` unless it's the working
    /// directory's own `.agents/skills`.
    public static func updateCommand(for skillsFolder: String, from workingDirectory: String) -> String {
        let own = URL(fileURLWithPath: workingDirectory).appendingPathComponent(".agents/skills").standardizedFileURL.path
        let folder = URL(fileURLWithPath: skillsFolder).standardizedFileURL.path
        guard folder != own else { return "gesturekit-drive install-skill --update" }
        let shown = folder.contains(" ") ? "\"\(folder)\"" : folder
        return "gesturekit-drive install-skill --update --into \(shown)"
    }
}
