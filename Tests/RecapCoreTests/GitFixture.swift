import Foundation
@testable import RecapCore

/// Builds a throwaway git repository in a temp directory for tests, so the
/// deterministic core can be exercised against real git output (PRD: shell out
/// to system git, so tests should too).
final class GitFixture {
    let path: String
    let git: Git

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("recap-wins-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.path = base.path
        self.git = Git(repositoryPath: base.path)

        try git.run(["init", "-q", "-b", "main"])
        try git.run(["config", "user.name", "Test User"])
        try git.run(["config", "user.email", "test@example.com"])
        try git.run(["config", "commit.gpgsign", "false"])
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Write a file (creating parent dirs) relative to the repo root.
    func write(_ relativePath: String, _ contents: String) throws {
        let url = URL(fileURLWithPath: path).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Stage everything and commit with the given subject, optional author.
    @discardableResult
    func commit(_ subject: String, authorName: String? = nil, authorEmail: String? = nil) throws -> String {
        try git.run(["add", "-A"])
        var args = ["commit", "-q", "-m", subject]
        if let name = authorName, let email = authorEmail {
            args += ["--author", "\(name) <\(email)>"]
        }
        try git.run(args)
        return try git.resolve("HEAD")
    }

    func checkout(newBranch name: String) throws {
        try git.run(["checkout", "-q", "-b", name])
    }

    func checkout(_ ref: String) throws {
        try git.run(["checkout", "-q", ref])
    }

    func merge(_ branch: String) throws {
        try git.run(["merge", "-q", "--no-ff", "-m", "merge \(branch)", branch])
    }
}
