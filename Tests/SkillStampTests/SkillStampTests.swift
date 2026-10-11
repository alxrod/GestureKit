import Testing
@testable import SkillStamp

private let revision = "409d7e2b2b6f0a4c8f1c3d5e7a9b0c2d4e6f8a1b"
private let other = "268a0460a12b41d6766dd7f9d3a2cf0653450f72"

private let unstamped = """
    ---
    name: verify-gestures
    description: Prove the gestures of a visionOS app built on GestureKit work.
    ---

    # Verify gestures on GestureKit

    metadata: in the body isn't frontmatter.
    """

/// `install-skill` stamps the copy's frontmatter, everything else as it
/// was, and the stamp reads back.
@Suite struct SkillStampFrontmatterTests {
    @Test("An unstamped skill gets a metadata map naming the revision, before the frontmatter closes")
    func stampsAnUnstampedSkill() throws {
        let stamped = try SkillStamp.stamping(unstamped, with: revision)
        #expect(stamped == """
            ---
            name: verify-gestures
            description: Prove the gestures of a visionOS app built on GestureKit work.
            metadata:
              gesturekit-revision: "\(revision)"
            ---

            # Verify gestures on GestureKit

            metadata: in the body isn't frontmatter.
            """)
        #expect(SkillStamp.revision(in: stamped) == revision)
        #expect(SkillStamp.revision(in: unstamped) == nil)
    }

    @Test("Stamping again replaces the stamp, and stamping with nil takes it and its empty metadata away")
    func restampsAndUnstamps() throws {
        let first = try SkillStamp.stamping(unstamped, with: revision)
        let second = try SkillStamp.stamping(first, with: other)
        #expect(SkillStamp.revision(in: second) == other)
        #expect(second.components(separatedBy: SkillStamp.metadataKey).count == 2)
        #expect(try SkillStamp.stamping(second, with: nil) == unstamped)
        #expect(try SkillStamp.stamping(unstamped, with: nil) == unstamped)
    }

    @Test("A metadata map the skill has keeps its entries and their indentation")
    func keepsOtherMetadata() throws {
        let skill = """
            ---
            name: verify-gestures
            metadata:
                author: someone
                version: "1.0"
            license: MIT
            ---
            Body.
            """
        let stamped = try SkillStamp.stamping(skill, with: revision)
        #expect(stamped == """
            ---
            name: verify-gestures
            metadata:
                author: someone
                version: "1.0"
                gesturekit-revision: "\(revision)"
            license: MIT
            ---
            Body.
            """)
        #expect(SkillStamp.revision(in: stamped) == revision)
        #expect(try SkillStamp.stamping(stamped, with: nil) == skill)
    }

    @Test("The stamp reads quoted, single-quoted, or bare, with a comment")
    func readsEachQuoting() {
        for line in ["\"\(revision)\"", "'\(revision)'", revision, "\(revision) # from install-skill"] {
            let skill = "---\nname: x\nmetadata:\n  gesturekit-revision: \(line)\n---\n"
            #expect(SkillStamp.revision(in: skill) == revision, "\(line)")
        }
        #expect(SkillStamp.revision(in: "---\nname: x\ngesturekit-revision: \(revision)\n---\n") == nil)
        #expect(SkillStamp.revision(in: "---\nname: x\nmetadata:\n  gesturekit-revision: \"\"\n---\n") == nil)
    }

    @Test("What can't be stamped is refused, saying why")
    func refusesWhatItCantStamp() {
        #expect(throws: SkillStamp.Problem.noFrontmatter) { try SkillStamp.stamping("# No frontmatter\n", with: revision) }
        #expect(throws: SkillStamp.Problem.noFrontmatter) { try SkillStamp.stamping("---\nname: x\n", with: revision) }
        #expect(throws: SkillStamp.Problem.inlineMetadata) {
            try SkillStamp.stamping("---\nname: x\nmetadata: {author: someone}\n---\n", with: revision)
        }
        #expect(throws: SkillStamp.Problem.notARevision("main")) { try SkillStamp.stamping(unstamped, with: "main") }
        #expect(throws: SkillStamp.Problem.notARevision("409d7e2")) { try SkillStamp.stamping(unstamped, with: "409d7e2") }
        #expect(SkillStamp.isRevision(String(repeating: "a", count: 64)))
        #expect(!SkillStamp.isRevision(revision.uppercased()))
    }
}

/// What git says of the checkout `gesturekit-drive` was built from decides
/// the stamp, and a stamp held against the driver's revision decides the
/// warning and `--update`.
@Suite struct SkillStampComparisonTests {
    @Test("Only a checkout of GestureKit's own, at a commit, with its skill as committed, gives a revision")
    func readsTheCheckoutsRevision() {
        let root = "/work/.build/checkouts/GestureKit"
        #expect(CheckoutRevision.reading(packageRoot: root, topLevel: root + "\n", head: revision + "\n", skillChanges: "") == .known(revision))
        #expect(CheckoutRevision.reading(packageRoot: root, topLevel: root + "/", head: revision, skillChanges: nil) == .known(revision))
        #expect(CheckoutRevision.reading(packageRoot: root, topLevel: nil, head: nil, skillChanges: nil).revision == nil)
        #expect(CheckoutRevision.reading(packageRoot: root, topLevel: "/work", head: revision, skillChanges: "") == .unknown(
            "GestureKit's folder, \(root), lies inside another git repository, /work, whose commit isn't GestureKit's"))
        #expect(CheckoutRevision.reading(packageRoot: root, topLevel: root, head: "fatal: bad", skillChanges: "").revision == nil)
        #expect(CheckoutRevision.reading(packageRoot: root, topLevel: root, head: revision,
                                         skillChanges: " M .agents/skills/verify-gestures/SKILL.md\n").revision == nil)
    }

    @Test("A stamp from another revision is out of step, and its warning names both and the update")
    func comparesStamps() {
        #expect(SkillStampComparison(installed: revision, driver: revision) == .inStep(revision))
        #expect(SkillStampComparison(installed: revision.uppercased(), driver: revision) == .inStep(revision))
        #expect(SkillStampComparison(installed: other, driver: revision) == .outOfStep(installed: other, driver: revision))
        #expect(SkillStampComparison(installed: nil, driver: revision) == .unstamped)
        #expect(SkillStampComparison(installed: nil, driver: nil) == .unstamped)
        #expect(SkillStampComparison(installed: other, driver: nil) == .driverUnknown(installed: other))

        let update = "gesturekit-drive install-skill --update"
        let warning = SkillStampComparison(installed: other, driver: revision).warning(skill: ".agents/skills/verify-gestures", update: update)
        #expect(warning == "gesturekit-drive: the verify-gestures skill at .agents/skills/verify-gestures came from GestureKit \(other), but this gesturekit-drive is GestureKit \(revision); bring the skill in step with: \(update)")
        for quiet in [SkillStampComparison.inStep(revision), .unstamped, .driverUnknown(installed: other)] {
            #expect(quiet.warning(skill: "x", update: update) == nil)
        }
    }

    @Test("--update replaces only a copy from another revision, or unstamped; --replace replaces any; neither refuses")
    func plansAnInstall() {
        #expect(SkillInstallPlan.plan(exists: false, installed: nil, revision: revision, replaces: false, updates: false) == .install)
        #expect(SkillInstallPlan.plan(exists: false, installed: nil, revision: nil, replaces: false, updates: true) == .install)
        #expect(SkillInstallPlan.plan(exists: true, installed: revision, revision: revision, replaces: false, updates: true) == .keep(revision))
        #expect(SkillInstallPlan.plan(exists: true, installed: other, revision: revision, replaces: false, updates: true) == .replace(from: other))
        #expect(SkillInstallPlan.plan(exists: true, installed: nil, revision: revision, replaces: false, updates: true) == .replace(from: nil))
        #expect(SkillInstallPlan.plan(exists: true, installed: revision, revision: revision, replaces: true, updates: false) == .replace(from: revision))
        if case .refuse = SkillInstallPlan.plan(exists: true, installed: other, revision: nil, replaces: false, updates: true) {} else {
            Issue.record("--update with a driver of unknown revision should refuse")
        }
        if case .refuse = SkillInstallPlan.plan(exists: true, installed: other, revision: revision, replaces: false, updates: false) {} else {
            Issue.record("a plain install over a copy should refuse")
        }
    }

    @Test("The installed copy is looked for from the working directory up to the git root, or in it alone outside git")
    func findsWhereToLook() {
        let roots: Set<String> = ["/work/app"]
        #expect(InstalledSkill.searchedDirectories(from: "/work/app/Sources/App/", isGitRoot: roots.contains)
                == ["/work/app/Sources/App", "/work/app/Sources", "/work/app"])
        #expect(InstalledSkill.searchedDirectories(from: "/work/app", isGitRoot: roots.contains) == ["/work/app"])
        #expect(InstalledSkill.searchedDirectories(from: "/elsewhere/deep", isGitRoot: roots.contains) == ["/elsewhere/deep"])
        #expect(InstalledSkill.updateCommand(for: "/work/app/.agents/skills", from: "/work/app") == "gesturekit-drive install-skill --update")
        #expect(InstalledSkill.updateCommand(for: "/work/app/.agents/skills", from: "/work/app/Sources")
                == "gesturekit-drive install-skill --update --into /work/app/.agents/skills")
        #expect(InstalledSkill.updateCommand(for: "/work/my app/.agents/skills", from: "/work")
                == "gesturekit-drive install-skill --update --into \"/work/my app/.agents/skills\"")
    }
}
