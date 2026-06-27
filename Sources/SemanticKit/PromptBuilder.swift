import Foundation
import RecapCore

/// Builds prompts for the semantic commands from a deterministic `ChangeReport`.
///
/// The model never sees raw git — it sees the already-classified, already-counted
/// report. That keeps the semantic layer grounded in verifiable facts (the core
/// did the counting) and the model's job narrow: turn structured change data into
/// the right prose for the target.
public enum PromptBuilder {
    /// A compact, factual rendering of the change set the model reasons over.
    /// Deterministic text — same report always yields the same context block.
    public static func contextBlock(_ report: ChangeReport) -> String {
        var lines: [String] = []
        let v = report.vitals
        lines.append("Change set: \(report.range.base)..\(report.range.head)")
        lines.append("Totals: \(v.features) features, \(v.fixes) fixes, \(v.chores) chores; "
            + "\(v.filesChanged) files changed (+\(v.insertions)/-\(v.deletions)).")

        let work = report.commits.filter { !$0.isMerge }
        if !work.isEmpty {
            lines.append("")
            lines.append("Commits (type — subject):")
            for c in work {
                let scope = c.scope.map { "(\($0))" } ?? ""
                let breaking = c.breaking ? " [BREAKING]" : ""
                let ticket = c.ticket.map { " {\($0)}" } ?? ""
                lines.append("- \(c.type.rawValue)\(scope)\(breaking): \(c.subject)\(ticket)")
            }
        }

        if !v.hotspots.isEmpty {
            lines.append("")
            lines.append("Most-changed files:")
            for f in v.hotspots {
                lines.append("- \(f.path) (+\(f.insertions)/-\(f.deletions))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// System + user prompt for `rw new` — list the new user-facing features.
    public static func newFeatures(_ report: ChangeReport) -> ModelRequest {
        let system = """
        You analyze a software change set and list the NEW USER-FACING FEATURES it \
        introduces. You are given a structured, already-classified summary of the \
        change — trust its counts and commit types as ground truth.

        Rules:
        - List only genuinely new capabilities a user or developer would notice. \
        Fold pure chores, refactors, dependency bumps, formatting, and test-only \
        changes OUT — they are not features.
        - Multiple commits often add up to ONE feature; collapse them.
        - One concise bullet per feature, imperative or noun phrase. No preamble, \
        no closing summary, no headings. If there are no real features, say exactly \
        "No new user-facing features in this change set."
        """
        let user = "Here is the change set:\n\n\(contextBlock(report))"
        return ModelRequest(
            system: system,
            messages: [ChatMessage(role: .user, text: user)],
            maxTokens: 800,
            temperature: 0.3
        )
    }

    /// System + user prompt for `rw notes --pr` — a PR description.
    public static func pullRequestNote(_ report: ChangeReport) -> ModelRequest {
        let system = """
        You write a clear, technical PULL REQUEST DESCRIPTION for a reviewer, from \
        a structured summary of a change set. Trust the provided counts and commit \
        types as ground truth.

        Structure the description with these sections (use Markdown headings):
        - "## Summary" — 1-3 sentences on what this change does and why.
        - "## What changed" — bulleted, grouped logically (features, fixes, chores).
        - "## Areas to review" — call out the riskiest or highest-churn spots a \
        reviewer should focus on, informed by the most-changed files.

        Be specific and factual; do not invent changes not present in the summary. \
        No marketing tone. Output only the description, no preamble.
        """
        let user = "Here is the change set:\n\n\(contextBlock(report))"
        return ModelRequest(
            system: system,
            messages: [ChatMessage(role: .user, text: user)],
            maxTokens: 1500,
            temperature: 0.4
        )
    }

    /// System + user prompt for a `rw notes` target (PRD §6.1). Renders the right
    /// tone, audience, and length for the destination, in the product's voice
    /// when the target is user-facing.
    public static func note(
        _ report: ChangeReport,
        target: NoteTarget,
        product: ProductProfile?,
        limit: ResolvedLimit
    ) -> ModelRequest {
        // --pr keeps its dedicated, section-structured prompt.
        if target == .pr { return pullRequestNote(report) }

        var system = persona(for: target)
        if target.usesProductVoice, let product {
            system += "\n\nWrite in this product's voice: \(product.voice). "
            system += "The product is named \(product.name)."
        }
        system += "\n\n" + lengthGuidance(limit)
        system += "\n\nGround every claim in the change set below; do not invent " +
            "changes. Output only the note text, no preamble, no headings unless natural."

        let user = "Here is the change set:\n\n\(contextBlock(report))"
        return ModelRequest(
            system: system,
            messages: [ChatMessage(role: .user, text: user)],
            maxTokens: maxTokens(for: limit),
            temperature: target.usesProductVoice ? 0.6 : 0.4
        )
    }

    /// The audience/tone instruction per target.
    private static func persona(for target: NoteTarget) -> String {
        switch target {
        case .pr:
            return "You write a technical PR description."
        case .ascReviewer:
            return """
            You write APP REVIEW NOTES for Apple's App Review team (private, not \
            shown to users). Cover: what changed in this build, any demo steps or \
            test credentials a reviewer needs, and why a feature behaves as it does. \
            Be direct and practical; this is to help a reviewer approve the build.
            """
        case .whatNew:
            return """
            You write beta-tester release notes ("What to Test"). Tell your testers \
            what changed in this build and what to exercise. Friendly and concrete.
            """
        case .ascUpdate, .gpUpdate:
            return """
            You write public app-store release notes ("What's New in This Version"). \
            User-facing: highlight what's new and improved in plain, benefit-led \
            language. No internal/technical jargon, no commit hashes.
            """
        case .changelog:
            return """
            You write a public CHANGELOG entry for a tagged release — the canonical \
            "what changed" artifact users see when they upgrade.

            Structure it with three Markdown sections, in this order, omitting any \
            section that's empty:
            - "## Added" — new user-facing features and capabilities.
            - "## Changed" — behavior changes, improvements, performance, docs.
            - "## Fixed" — bug fixes.

            Each item is one short bullet, benefit-led where possible, written for \
            a developer or end user who will read this in a browser or release page. \
            Do NOT include internal refactors, dependency bumps, or test-only \
            changes unless they shipped user-visible behavior. No commit hashes, \
            no PR numbers. No preamble — start with the first "## Added" heading.
            """
        }
    }

    /// Length instruction from the resolved limit: aim for the soft target, never
    /// exceed the hard ceiling.
    private static func lengthGuidance(_ limit: ResolvedLimit) -> String {
        if let soft = limit.softTarget {
            let ceil = limit.ceiling > 0 ? " Never exceed \(limit.ceiling) characters." : ""
            return "Aim for about \(soft) characters.\(ceil)"
        }
        if limit.ceiling > 0 {
            return "Keep it within \(limit.ceiling) characters — this is a hard limit."
        }
        return "Keep it tight and skimmable."
    }

    private static func maxTokens(for limit: ResolvedLimit) -> Int {
        // ~4 chars/token; give headroom. Default generous for uncapped targets.
        let chars = limit.ceiling > 0 ? limit.ceiling : 2000
        return min(2000, max(400, chars / 2))
    }

    /// System + user prompt for one `rw market` pack piece (PRD §6). Renders the
    /// new features as marketing copy in the product's voice, for one channel.
    public static func marketPiece(
        _ report: ChangeReport,
        piece: MarketPiece,
        product: ProductProfile,
        ceiling: Int
    ) -> ModelRequest {
        var system = """
        You write MARKETING COPY for an app, announcing what's new. Write in the \
        product's voice: \(product.voice). The product is named \(product.name).
        """
        if !product.links.isEmpty {
            system += "\nRelevant links (use only if natural): \(product.links.joined(separator: ", "))."
        }
        system += "\n\n" + pieceInstruction(piece)
        if ceiling > 0 {
            system += " Hard limit: \(ceiling) characters — do not exceed it."
        }
        system += "\n\nBase every claim on the change set below; do not invent " +
            "features. Benefit-led, no internal/technical jargon, no commit hashes. " +
            "Output only the copy itself — no label, no preamble, no quotes."

        let user = "Here is the change set:\n\n\(contextBlock(report))"
        return ModelRequest(
            system: system,
            messages: [ChatMessage(role: .user, text: user)],
            maxTokens: ceiling > 0 ? min(600, max(120, ceiling / 2)) : 700,
            temperature: 0.7
        )
    }

    /// Per-piece channel/format instruction.
    private static func pieceInstruction(_ piece: MarketPiece) -> String {
        switch piece {
        case .whatsNew:
            return "Write an App Store \"What's New\" announcement: a few punchy " +
                "lines leading with the most exciting new feature."
        case .promotionalText:
            return "Write App Store promotional text: one or two vivid sentences " +
                "highlighting what's new, meant to sit above the description."
        case .subtitle:
            return "Write an App Store subtitle: a single, tight tagline-length phrase."
        case .shortDescription:
            return "Write a Google Play short description: one compelling sentence " +
                "about what the app now does."
        case .post:
            return "Write a short social post announcing the update — friendly, " +
                "skimmable, one or two short paragraphs, light on hashtags."
        case .tweet:
            return "Write a single tweet announcing the update — punchy, one sentence " +
                "or two, at most one hashtag."
        }
    }
}
