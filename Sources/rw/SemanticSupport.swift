import ArgumentParser
import Foundation
import RecapCore
import SemanticKit

/// Shared plumbing for the semantic commands (`new`, `notes`): build the report,
/// load config, resolve the model client, and surface a clean error if the key
/// is missing rather than a stack trace.
extension ChangeSetOptions {
    /// Load repo config (testthese.toml), falling back to defaults.
    func loadConfig() throws -> Config {
        try Config.load(fromRepo: repo)
    }

    /// Build the report using the config's base when the user didn't override it.
    /// `--base` on the command line always wins; otherwise the config's `base`.
    func buildReport(config: Config) throws -> ChangeReport {
        let resolvedBase = (base == "main") ? config.base : base
        let git = Git(repositoryPath: repo)
        let builder = ChangeReportBuilder(git: git)
        return try builder.build(base: resolvedBase, head: head)
    }

    /// Resolve a live model client, mapping a missing key to a clean exit.
    func makeSemanticEngine(config: Config) throws -> SemanticEngine {
        do {
            let client = try ModelConfig.makeClient(config: config)
            return SemanticEngine(client: client)
        } catch let error as ModelError {
            throw ValidationError(error.description)
        }
    }
}

/// Run an async throwing body from a synchronous `run()`, surfacing model errors
/// as clean CLI messages.
func runAsync(_ body: @escaping @Sendable () async throws -> Void) throws {
    let box = ResultBox()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do { try await body() }
        catch { box.error = error }
        semaphore.signal()
    }
    semaphore.wait()
    if let error = box.error {
        if let modelError = error as? ModelError {
            throw ValidationError(modelError.description)
        }
        throw error
    }
}

/// Minimal mutable box to carry a thrown error out of the Task.
private final class ResultBox: @unchecked Sendable {
    var error: Error?
}
