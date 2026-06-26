import Foundation

/// Errors surfaced by the git layer.
public enum GitError: Error, CustomStringConvertible, Equatable {
    /// A git invocation exited non-zero. Carries stderr for diagnostics.
    case commandFailed(arguments: [String], exitCode: Int32, stderr: String)
    /// `git` produced output we couldn't parse into the expected shape.
    case unexpectedOutput(String)
    /// The working directory isn't inside a git repository.
    case notARepository(path: String)
    /// A ref couldn't be resolved to a commit (typo, or a repo with no commits).
    case unresolvableRef(String)

    public var description: String {
        switch self {
        case let .commandFailed(arguments, exitCode, stderr):
            let cmd = (["git"] + arguments).joined(separator: " ")
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(cmd)` failed (exit \(exitCode))\(detail.isEmpty ? "" : ": \(detail)")"
        case let .unexpectedOutput(detail):
            return "Unexpected git output: \(detail)"
        case let .notARepository(path):
            return "Not a git repository: \(path)"
        case let .unresolvableRef(ref):
            return "Could not resolve ref '\(ref)' to a commit. "
                + "Check the name, or note that a repo with no commits yet has nothing to diff."
        }
    }
}

/// Thin wrapper around the system `git` binary, scoped to one repository.
///
/// PRD §9: shell out to system git for zero dependencies and behavior identical
/// to commands run by hand. Everything here is deterministic and offline.
public struct Git: Sendable {
    /// Absolute path to the repository working directory.
    public let repositoryPath: String

    public init(repositoryPath: String) {
        self.repositoryPath = repositoryPath
    }

    /// Run `git <arguments>` in the repository and return trimmed stdout.
    ///
    /// `core.quotePath=false` is forced on every invocation so git emits UTF-8
    /// paths literally instead of octal-escaping non-ASCII bytes and wrapping
    /// them in quotes (e.g. `"caf\303\251.swift"`). Without it, file paths with
    /// non-ASCII characters come back mangled — a real problem for the
    /// international repos recap-wins targets.
    @discardableResult
    public func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-c", "core.quotePath=false"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: repositoryPath)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw GitError.commandFailed(
                arguments: arguments,
                exitCode: -1,
                stderr: "could not launch git: \(error.localizedDescription)"
            )
        }

        // Read before waitUntilExit to avoid deadlock on large output.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let outString = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(
                arguments: arguments,
                exitCode: process.terminationStatus,
                stderr: String(decoding: errData, as: UTF8.self)
            )
        }
        return outString
    }

    /// Verify the path is inside a git work tree, throwing otherwise.
    public func ensureRepository() throws {
        let inside: String
        do {
            inside = try run(["rev-parse", "--is-inside-work-tree"])
        } catch {
            throw GitError.notARepository(path: repositoryPath)
        }
        guard inside.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw GitError.notARepository(path: repositoryPath)
        }
    }

    /// Resolve a ref to its full commit SHA.
    public func resolve(_ ref: String) throws -> String {
        do {
            return try run(["rev-parse", "--verify", "\(ref)^{commit}"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw GitError.unresolvableRef(ref)
        }
    }

    /// The merge-base (fork point) of two refs — where the diff is computed from.
    public func mergeBase(_ a: String, _ b: String) throws -> String {
        try run(["merge-base", a, b])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name of the current branch, or nil in detached-HEAD state.
    public func currentBranch() throws -> String? {
        let name = try run(["rev-parse", "--abbrev-ref", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name == "HEAD" ? nil : name
    }
}
