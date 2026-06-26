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
}
