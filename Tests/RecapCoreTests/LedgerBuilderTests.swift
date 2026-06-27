import Testing
import Foundation
@testable import RecapCore

@Suite("LedgerBuilder (against real git)")
struct LedgerBuilderTests {
    // MARK: - Title cleaning (pure)

    @Test("conventional-commit prefixes are stripped from the ledger title")
    func cleanedTitlesStripPrefixes() {
        let g = Git(repositoryPath: "/tmp")  // path unused for cleanedTitle
        let b = LedgerBuilder(git: g)
        #expect(b.cleanedTitle("feat: add CSV export") == "add CSV export")
        #expect(b.cleanedTitle("feat(auth): SSO") == "SSO")
        #expect(b.cleanedTitle("feat(payments)!: switch to Stripe") == "switch to Stripe")
        // Non-conventional subjects come through unchanged.
        #expect(b.cleanedTitle("Add SSO support") == "Add SSO support")
        // Defensive: empty subject doesn't crash.
        #expect(b.cleanedTitle("") == "")
    }

    // MARK: - End-to-end build

    @Test("builds a ledger of feat-prefixed commits")
    func ledgerFromFeats() throws {
        let fx = try GitFixture()
        try fx.write("README.md", "x")
        try fx.commit("chore: init")
        try fx.write("a.swift", "1")
        try fx.commit("feat: add A")
        try fx.write("b.swift", "1")
        try fx.commit("feat(core): add B")
        try fx.write("c.swift", "1")
        try fx.commit("fix: something")

        let ledger = try LedgerBuilder(git: fx.git).build(
            portName: "ios", ref: "HEAD", since: nil)

        #expect(ledger.portName == "ios")
        #expect(ledger.features.count == 2)
        #expect(ledger.features.map(\.title) == ["add A", "add B"])
        #expect(ledger.features.allSatisfy { $0.origin == .declared })
        #expect(ledger.features[1].scope == "core")
    }

    @Test("non-conventional feature verbs are inferred and flagged")
    func ledgerInfersFeatures() throws {
        let fx = try GitFixture()
        try fx.write("init.swift", "1")
        try fx.commit("chore: init")
        try fx.write("export.swift", "1")
        try fx.commit("Add CSV export")          // looks like a feature
        try fx.write("typo.swift", "1")
        try fx.commit("typo")                    // not a feature

        let ledger = try LedgerBuilder(git: fx.git).build(
            portName: "x", ref: "HEAD", since: nil)

        #expect(ledger.features.count == 1)
        #expect(ledger.features[0].title == "Add CSV export")
        #expect(ledger.features[0].origin == .inferred)
    }

    @Test("merge commits are excluded from the ledger")
    func ledgerExcludesMerges() throws {
        let fx = try GitFixture()
        try fx.write("seed.swift", "1")
        try fx.commit("chore: init")
        try fx.checkout(newBranch: "feature")
        try fx.write("feat.swift", "1")
        try fx.commit("feat: branch feature")
        try fx.checkout("main")
        try fx.merge("feature")

        let ledger = try LedgerBuilder(git: fx.git).build(
            portName: "x", ref: "HEAD", since: nil)
        // Exactly one feature; the merge commit doesn't add a duplicate.
        #expect(ledger.features.count == 1)
        #expect(ledger.features[0].title == "branch feature")
    }

    @Test("since baseline drops features predating the tag")
    func ledgerHonorsSinceBaseline() throws {
        let fx = try GitFixture()
        try fx.write("seed.swift", "1")
        try fx.commit("chore: init")
        try fx.write("old.swift", "1")
        try fx.commit("feat: old feature")
        // Tag this point as the port-start baseline.
        try fx.git.run(["tag", "v1.0"])
        try fx.write("new.swift", "1")
        try fx.commit("feat: new feature")

        let withBaseline = try LedgerBuilder(git: fx.git).build(
            portName: "x", ref: "HEAD", since: "v1.0")
        let withoutBaseline = try LedgerBuilder(git: fx.git).build(
            portName: "x", ref: "HEAD", since: nil)

        #expect(withBaseline.features.map(\.title) == ["new feature"])
        #expect(withoutBaseline.features.map(\.title) == ["old feature", "new feature"])
        #expect(withBaseline.since == "v1.0")
        #expect(withBaseline.sinceSHA != nil)
    }

    @Test("non-feature types (fix/chore/docs) don't appear in the ledger")
    func ledgerDropsNonFeatures() throws {
        let fx = try GitFixture()
        try fx.write("seed.swift", "1")
        try fx.commit("chore: init")
        try fx.write("a.swift", "1")
        try fx.commit("fix: bug")
        try fx.write("b.swift", "1")
        try fx.commit("docs: tweak")
        try fx.write("c.swift", "1")
        try fx.commit("refactor: rename")

        let ledger = try LedgerBuilder(git: fx.git).build(
            portName: "x", ref: "HEAD", since: nil)
        #expect(ledger.features.isEmpty)
    }

    @Test("snapshot pins headSHA so re-runs detect drift")
    func snapshotPinsHead() throws {
        let fx = try GitFixture()
        try fx.write("a", "1")
        try fx.commit("feat: a")
        let firstHead = try fx.git.resolve("HEAD")

        let ledger = try LedgerBuilder(git: fx.git).build(
            portName: "x", ref: "HEAD", since: nil)
        #expect(ledger.headSHA == firstHead)

        // Add a new commit and rebuild — headSHA must advance.
        try fx.write("b", "1")
        try fx.commit("feat: b")
        let newHead = try fx.git.resolve("HEAD")
        let updated = try LedgerBuilder(git: fx.git).build(
            portName: "x", ref: "HEAD", since: nil)
        #expect(updated.headSHA == newHead)
        #expect(updated.headSHA != ledger.headSHA)
    }

    // MARK: - Real-repo smoke test (skipped when env vars unset)

    /// When RW_TEST_LEDGERLY_IOS and RW_TEST_LEDGERLY_ANDROID point at real
    /// Ledgerly port checkouts, build both ledgers and assert they look sane.
    /// Skipped silently in CI / on machines without those checkouts.
    @Test("real Ledgerly ports build sane ledgers (RW_TEST_LEDGERLY_*)")
    func realLedgerlyPorts() throws {
        let env = ProcessInfo.processInfo.environment
        guard let iosPath = env["RW_TEST_LEDGERLY_IOS"],
              let androidPath = env["RW_TEST_LEDGERLY_ANDROID"],
              !iosPath.isEmpty, !androidPath.isEmpty else {
            // Not configured on this machine — skip without complaint.
            return
        }
        let iosLedger = try LedgerBuilder(git: Git(repositoryPath: iosPath))
            .build(portName: "ios", ref: "main", since: env["RW_TEST_LEDGERLY_SINCE"])
        let androidLedger = try LedgerBuilder(git: Git(repositoryPath: androidPath))
            .build(portName: "android", ref: "main", since: env["RW_TEST_LEDGERLY_SINCE"])

        // Just sanity: both have a head SHA and at least one feature each.
        // Tighter assertions would be brittle against your real history.
        #expect(!iosLedger.headSHA.isEmpty)
        #expect(!androidLedger.headSHA.isEmpty)
        // Don't assert specific feature counts; either side could have zero
        // after a baseline. The goal is "this ran end-to-end without error".
    }
}
