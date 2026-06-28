import ArgumentParser
import Foundation
import RecapCore
import SemanticKit

/// Options group for commit comparison commands
struct ComparisonOptions: ParsableArguments {
    @Argument(help: "Initial commit ID or reference (or commit1..commit2 range)")
    var initialCommit: String

    @Argument(help: "Final commit ID or reference (omit if using range syntax)")
    var finalCommit: String = ""

    @Option(name: .long, help: "Path to the git repository. Default: current directory.")
    var repo: String = FileManager.default.currentDirectoryPath

    /// Build a change report comparing the two commits
    func buildComparisonReport() throws -> ChangeReport {
        let git = Git(repositoryPath: repo)
        let builder = ChangeReportBuilder(git: git)

        // Support both individual commits and range syntax (e.g., "v1.0.0..v2.0.0")
        let (base, head) = try parseCommitRange()
        return try builder.build(base: base, head: head)
    }

    /// Parse commit arguments - supports both "commit1 commit2" and "commit1..commit2" syntax
    private func parseCommitRange() throws -> (base: String, head: String) {
        // Check if first argument contains range syntax (looking for ".." specifically)
        if let rangeIndex = initialCommit.range(of: "..") {
            let base = String(initialCommit[..<rangeIndex.lowerBound])
            let head = String(initialCommit[rangeIndex.upperBound...])

            guard !base.isEmpty && !head.isEmpty else {
                throw ValidationError("Invalid range syntax. Use 'commit1..commit2' or provide two separate commits.")
            }
            return (base: base, head: head)
        } else {
            // Two separate commits provided
            guard !finalCommit.isEmpty else {
                throw ValidationError("Provide either two commits (commit1 commit2) or a range (commit1..commit2)")
            }
            return (base: initialCommit, head: finalCommit)
        }
    }
}

/// `rw draft` — Generate a draft (PR description, changelog, etc.) from commit comparison
struct Draft: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a draft from comparing two commits (PR description, changelog, etc.)"
    )

    @OptionGroup var comparison: ComparisonOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Backend: anthropic (API), skill (key-free, emits JSON), openai, gemini.")
    var provider: String?

    @Option(name: .long, help: "Draft type: pr (default), changelog, summary")
    var type: String = "pr"

    @Option(name: .long, help: "API key for the selected provider (if not in env vars)")
    var apiKey: String?

    @Option(name: .long, help: "Local skill file to use instead of API providers")
    var skill: String?

    func validate() throws {
        // Ensure we have either two commits or a range
        if !comparison.initialCommit.contains("..") && comparison.finalCommit.isEmpty {
            throw ValidationError("Provide either two commits (commit1 commit2) or a range (commit1..commit2)")
        }
    }

    func run() throws {
        let config = try Config.load(fromRepo: comparison.repo)
        let report = try comparison.buildComparisonReport()

        if output.json {
            try emitJSON(report)
            return
        }

        let selectedProvider = try resolveProvider(flag: provider, config: config)

        // Skill mode: emit the envelope for the host agent
        if selectedProvider == .skill || skill != nil {
            if output.wantsHTML {
                throw ValidationError(
                    "--html doesn't apply in skill mode (the host agent renders, "
                    + "not rw). Run without --provider skill, or render the agent's "
                    + "output yourself.")
            }

            let envelope = SkillEnvelope.forDraft(report, type: type)
            print(try envelope.jsonString())
            return
        }

        // API mode: call the provider
        let engine = try makeSemanticEngine(config: config, provider: selectedProvider, apiKey: apiKey)
        let wantsHTML = output.wantsHTML
        let htmlOut = output.htmlOut
        let openInBrowser = output.open
        let repoPath = comparison.repo
        let range = report.range

        try runAsync {
            let draft = try await engine.draft(report, type: type)
            if wantsHTML {
                let html = HTMLRender.draft(draft, type: type, range: range)
                try writeHTMLReport(
                    html, command: "draft-\(type)", range: range, repoPath: repoPath,
                    outPath: htmlOut, open: openInBrowser)
            } else {
                print(draft)
            }
        }
    }
}

/// `rw release-notes` — Generate release notes for app stores from commit comparison
struct ReleaseNotes: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate release notes for app stores from comparing two commits"
    )

    @OptionGroup var comparison: ComparisonOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Target platform: app-store, play-store, testflight (default)")
    var platform: String = "testflight"

    @Option(name: .long, help: "Product id for voice + platform (required for store targets)")
    var product: String?

    @Option(name: .long, help: "Backend: anthropic (API), skill (key-free, emits JSON), openai, gemini.")
    var provider: String?

    @Option(name: .long, help: "API key for the selected provider (if not in env vars)")
    var apiKey: String?

    @Option(name: .long, help: "Local skill file to use instead of API providers")
    var skill: String?

    @Option(name: .long, help: "Character limit for the release notes")
    var limit: Int?

    func validate() throws {
        // Ensure we have either two commits or a range
        if !comparison.initialCommit.contains("..") && comparison.finalCommit.isEmpty {
            throw ValidationError("Provide either two commits (commit1 commit2) or a range (commit1..commit2)")
        }
    }

    func run() throws {
        let config = try Config.load(fromRepo: comparison.repo)
        let report = try comparison.buildComparisonReport()

        if output.json {
            try emitJSON(report)
            return
        }

        // Map platform to note target
        let target: NoteTarget = switch platform {
        case "app-store": .ascUpdate
        case "play-store": .gpUpdate
        case "testflight": .whatNew
        default: .whatNew
        }

        // Resolve product profile if needed
        let profile = product.flatMap { config.product($0) }
        if target.requiresProduct && profile == nil {
            throw ValidationError(
                "\(platform) release notes require --product <id> for the product's voice. Check testthese.toml."
            )
        }

        let selectedProvider = try resolveProvider(flag: provider, config: config)

        // Skill mode
        if selectedProvider == .skill || skill != nil {
            if output.wantsHTML {
                throw ValidationError(
                    "--html doesn't apply in skill mode (the host agent renders, "
                    + "not rw). Run without --provider skill, or render the agent's "
                    + "output yourself.")
            }

            try runAsync {
                let resolved = try await resolveNoteLimit(
                    config: config, target: target, profile: profile,
                    userLimit: limit, refresh: false)
                let envelope = SkillEnvelope.forNote(
                    report, target: target, product: profile, limit: resolved)
                print(try envelope.jsonString())
            }
            return
        }

        // API mode
        let engine = try makeSemanticEngine(config: config, provider: selectedProvider, apiKey: apiKey)
        let wantsHTML = output.wantsHTML
        let htmlOut = output.htmlOut
        let openInBrowser = output.open
        let repoPath = comparison.repo
        let range = report.range

        try runAsync {
            let resolved = try await resolveNoteLimit(
                config: config, target: target, profile: profile,
                userLimit: limit, refresh: false)
            let result = try await engine.note(report, target: target, product: profile, limit: resolved)

            if wantsHTML {
                let html = HTMLRender.notes(
                    result.text, target: target, limit: resolved,
                    product: profile, range: range)
                try writeHTMLReport(
                    html, command: "release-notes-\(platform)", range: range,
                    repoPath: repoPath, outPath: htmlOut, open: openInBrowser)
            } else {
                print(result.text)
            }

            if let warning = result.overflowWarning {
                FileHandle.standardError.write(Data(("\n⚠ " + warning + "\n").utf8))
            }
        }
    }
}

/// `rw marketing` — Generate marketing copy from commit comparison
struct MarketingCopy: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "marketing",
        abstract: "Generate marketing copy from comparing two commits"
    )

    @OptionGroup var comparison: ComparisonOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Marketing format: blog, social, email, announcement (default)")
    var format: String = "announcement"

    @Option(name: .long, help: "Product id for voice + branding")
    var product: String?

    @Option(name: .long, help: "Backend: anthropic (API), skill (key-free, emits JSON), openai, gemini.")
    var provider: String?

    @Option(name: .long, help: "API key for the selected provider (if not in env vars)")
    var apiKey: String?

    @Option(name: .long, help: "Local skill file to use instead of API providers")
    var skill: String?

    func validate() throws {
        // Ensure we have either two commits or a range
        if !comparison.initialCommit.contains("..") && comparison.finalCommit.isEmpty {
            throw ValidationError("Provide either two commits (commit1 commit2) or a range (commit1..commit2)")
        }
    }

    func run() throws {
        let config = try Config.load(fromRepo: comparison.repo)
        let report = try comparison.buildComparisonReport()

        if output.json {
            try emitJSON(report)
            return
        }

        let profile = product.flatMap { config.product($0) }
        let selectedProvider = try resolveProvider(flag: provider, config: config)

        // Skill mode
        if selectedProvider == .skill || skill != nil {
            if output.wantsHTML {
                throw ValidationError(
                    "--html doesn't apply in skill mode (the host agent renders, "
                    + "not rw). Run without --provider skill, or render the agent's "
                    + "output yourself.")
            }

            let envelope = SkillEnvelope.forMarketing(report, format: format, product: profile)
            print(try envelope.jsonString())
            return
        }

        // API mode
        let engine = try makeSemanticEngine(config: config, provider: selectedProvider, apiKey: apiKey)
        let wantsHTML = output.wantsHTML
        let htmlOut = output.htmlOut
        let openInBrowser = output.open
        let repoPath = comparison.repo
        let range = report.range

        try runAsync {
            let marketing = try await engine.marketing(report, format: format, product: profile)

            if wantsHTML {
                let html = HTMLRender.marketing(marketing, format: format, product: profile, range: range)
                try writeHTMLReport(
                    html, command: "marketing-\(format)", range: range,
                    repoPath: repoPath, outPath: htmlOut, open: openInBrowser)
            } else {
                print(marketing)
            }
        }
    }
}

// MARK: - Helper functions for resolving the limit (making it accessible)

func resolveNoteLimit(
    config: Config,
    target: NoteTarget,
    profile: ProductProfile?,
    userLimit: Int?,
    refresh: Bool
) async throws -> ResolvedLimit {
    let limitsProvider = LimitsProvider(config: config)
    let ceilings = await limitsProvider.limits(forceRefresh: refresh)
    return ResolvedLimit.resolve(
        target: target,
        platform: profile?.platform ?? .iOS,
        limits: ceilings,
        softTarget: profile?.softTarget(for: target),
        userLimit: userLimit
    )
}

private func makeSemanticEngine(config: Config, provider: Provider, apiKey: String? = nil) throws -> SemanticEngine {
    do {
        let client = try ModelConfig.makeClient(for: provider, config: config)
        return SemanticEngine(client: client)
    } catch let error as ModelError {
        throw ValidationError(error.description)
    } catch let error as ProviderUnavailable {
        throw ValidationError(error.description)
    }
}

// Extensions to existing types for new functionality
extension SkillEnvelope {
    static func forDraft(_ report: ChangeReport, type: String) -> SkillEnvelope {
        let instruction = "Generate a \(type) draft from the change set. Output only the draft text."
        let system = "You are a technical writer. Generate a clear and concise \(type) based on the provided changes."
        let user = "Change report: \(report.commits.count) commits, \(report.files.count) files changed."

        return SkillEnvelope(
            schemaVersion: 1,
            command: "draft",
            target: type,
            instruction: instruction,
            system: system,
            user: user,
            softTargetChars: nil,
            ceilingChars: 0,
            report: report
        )
    }

    static func forMarketing(_ report: ChangeReport, format: String, product: ProductProfile?) -> SkillEnvelope {
        let instruction = "Generate \(format) marketing copy from the change set. Output only the marketing text."
        let system = "You are a marketing copywriter. Generate compelling \(format) copy based on the provided changes."
        let user = "Change report: \(report.commits.count) commits, \(report.files.count) files changed."

        return SkillEnvelope(
            schemaVersion: 1,
            command: "marketing",
            target: format,
            instruction: instruction,
            system: system,
            user: user,
            softTargetChars: nil,
            ceilingChars: 0,
            report: report
        )
    }
}

extension HTMLRender {
    static func draft(_ text: String, type: String, range: ChangeRange) -> String {
        // Reuse existing HTML rendering infrastructure similar to other commands
        let content = """
        <div class="prose">
        <h1>Draft: \(type)</h1>
        <p class="range">Comparing \(range.base) to \(range.head)</p>
        <div class="content">\(text)</div>
        </div>
        """
        return wrapInStandardHTML(content: content, title: "Draft: \(type)")
    }

    static func marketing(_ text: String, format: String, product: ProductProfile?, range: ChangeRange) -> String {
        let title = "Marketing Copy: \(format)"
        let content = """
        <div class="prose">
        <h1>\(title)</h1>
        <p class="range">Comparing \(range.base) to \(range.head)</p>
        \(product.map { "<p class=\"product\">Product: \($0.name)</p>" } ?? "")
        <div class="content">\(text)</div>
        </div>
        """
        return wrapInStandardHTML(content: content, title: title)
    }

    private static func wrapInStandardHTML(content: String, title: String) -> String {
        // This would use the same styling as other commands
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>\(title)</title>
            <style>
                body { font-family: system-ui, -apple-system, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; }
                h1 { font-size: 24px; margin-bottom: 8px; }
                .range { color: #666; font-size: 14px; margin-bottom: 20px; }
                .product { color: #444; font-size: 14px; margin-bottom: 12px; }
                .content { line-height: 1.6; }
            </style>
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
    }
}

extension SemanticEngine {
    func draft(_ report: ChangeReport, type: String) async throws -> String {
        // Build appropriate prompts based on draft type
        let systemPrompt = "You are a technical writer. Generate a clear and concise \(type) based on the provided changes."

        var authorList: [String] = []
        for commit in report.commits {
            authorList.append(commit.authorName)
        }
        let uniqueAuthors = Set(authorList)

        let userPrompt = """
        Generate a \(type) for these changes:

        Commits: \(report.commits.count)
        Files changed: \(report.files.count)
        Authors: \(uniqueAuthors.joined(separator: ", "))
        """

        let request = ModelRequest(
            system: systemPrompt,
            messages: [ChatMessage(role: .user, text: userPrompt)]
        )

        return try await client.complete(request)
    }

    func marketing(_ report: ChangeReport, format: String, product: ProductProfile?) async throws -> String {
        let systemPrompt = "You are a marketing copywriter. Generate compelling \(format) copy."

        var productInfo = ""
        if let product = product {
            productInfo = "\nProduct: \(product.name)\nPlatform: \(product.platform)"
        }

        let userPrompt = """
        Generate \(format) marketing copy for these changes:

        Commits: \(report.commits.count)
        Files changed: \(report.files.count)\(productInfo)
        """

        let request = ModelRequest(
            system: systemPrompt,
            messages: [ChatMessage(role: .user, text: userPrompt)]
        )

        return try await client.complete(request)
    }
}