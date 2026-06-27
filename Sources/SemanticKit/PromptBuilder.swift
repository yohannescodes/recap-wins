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

    /// System + user prompt for `rw align`'s parity matcher (FRD §6/§7).
    ///
    /// The model receives the two deterministic ledgers and the merged
    /// equivalence table (built-in Apple↔Google pairs + per-product curated
    /// entries), and returns a JSON document classifying each feature into
    /// paired / equivalent / gap_on_a / gap_on_b / ambiguous, with a
    /// confidence score. Issue drafts for confirmed gaps come back in the
    /// same response so we make ONE model call per align run, not two.
    ///
    /// The prompt's central rule is the FRD's anti-overclaim guard
    /// (§3, §11): never assert authoritative parity, always surface
    /// confidence, prefer `ambiguous` over a confidently-wrong match.
    public static func alignMatch(
        ledgerA: LedgerSnapshot,
        ledgerB: LedgerSnapshot,
        equivalences: [ParityEntry],
        productName: String?
    ) -> ModelRequest {
        var system = """
        You are the parity matcher for `rw align`. You compare TWO ports of \
        the same product (different repos, different languages, no shared \
        git history) and classify each feature as one of:
        - "paired"       — same capability on both sides; real parity.
        - "equivalent"   — different but platform-native substitutes \
        (Apple Pay ↔ Google Pay). Parity ACHIEVED, not a gap.
        - "gap_on_a"     — present on side B only; real missing work on side A.
        - "gap_on_b"     — present on side A only; real missing work on side B.
        - "ambiguous"    — you aren't sure; surface for human confirmation, \
        NEVER auto-classify as a gap when uncertain.

        Hard rules:
        1. NEVER assert authoritative parity. You are an assistant, not an \
        oracle. Always surface a confidence score (0.0–1.0).
        2. When in doubt, prefer "ambiguous". A confidently-wrong match is \
        worse than an admitted unknown — it makes the user relax when they \
        shouldn't.
        3. Respect the equivalence table provided. Pairs listed there are \
        platform-native substitutes — classify them as "equivalent" with \
        high confidence and reference the table in `equivalenceNote`.
        4. Weight DECLARED feature claims (origin: declared) higher than \
        INFERRED ones (origin: inferred). An inferred feature paired with \
        anything leans toward "ambiguous" unless the equivalence table or \
        the titles obviously match.
        5. For confirmed "gap_on_a" or "gap_on_b" items (NOT ambiguous, NOT \
        equivalent), generate an `IssueDraft` so the user can paste it into \
        their tracker. The draft body should be tracker-agnostic Markdown \
        explaining what the other side has and what the missing side needs \
        to ship to reach parity.
        6. For "paired" and "equivalent" items, do NOT generate issue drafts.

        Return a single JSON object with this exact shape, no preamble:
        {
          "features": [
            {
              "id": "string (unique within this response, e.g. m1, m2)",
              "status": "paired" | "equivalent" | "gap_on_a" | "gap_on_b" | "ambiguous",
              "descriptionA": "string or null (the side-A feature title, if present)",
              "descriptionB": "string or null (the side-B feature title, if present)",
              "equivalenceNote": "string or null (why these were treated as equivalent)",
              "confidence": 0.0 to 1.0
            }
          ],
          "issues": [
            {
              "side": "string (port name where work is needed, e.g. \\"ios\\" or \\"android\\")",
              "title": "string (short issue title)",
              "body": "string (markdown body explaining the gap and the work)",
              "sourceFeature": "string (the title of the feature on the ahead side that motivated this)"
            }
          ]
        }
        """
        if let productName {
            system += "\n\nThe product is \(productName). Use this when wording issue drafts."
        }

        let user = buildAlignUserBlock(
            ledgerA: ledgerA, ledgerB: ledgerB, equivalences: equivalences)

        return ModelRequest(
            system: system,
            messages: [ChatMessage(role: .user, text: user)],
            // Generous: long histories with dozens of features can produce a
            // sizeable JSON. Cap below a reasonable limit so we don't blow
            // through context on pathological repos.
            maxTokens: 4000,
            temperature: 0.2
        )
    }

    /// Build the user-message block the matcher reasons over: side A's
    /// features, side B's features, and the merged equivalence table.
    public static func buildAlignUserBlock(
        ledgerA: LedgerSnapshot,
        ledgerB: LedgerSnapshot,
        equivalences: [ParityEntry]
    ) -> String {
        var lines: [String] = []
        lines.append("PORTS")
        lines.append("- side A: name=\(ledgerA.portName) ref=\(ledgerA.ref) head=\(ledgerA.headSHA.prefix(7))")
        lines.append("- side B: name=\(ledgerB.portName) ref=\(ledgerB.ref) head=\(ledgerB.headSHA.prefix(7))")
        if let since = ledgerA.since ?? ledgerB.since {
            lines.append("- since baseline: \(since)")
        }
        lines.append("")
        lines.append("EQUIVALENCE TABLE (platform-native substitutes; treat matches here as \"equivalent\", not gaps)")
        if equivalences.isEmpty {
            lines.append("- (none configured; rely on the system prompt's general guidance)")
        } else {
            for entry in equivalences {
                let note = entry.note.map { " — \($0)" } ?? ""
                lines.append("- A: \(entry.a)  ↔  B: \(entry.b)\(note)")
            }
        }
        lines.append("")
        lines.append("SIDE A FEATURES (\(ledgerA.features.count))")
        for f in ledgerA.features {
            lines.append("- [\(f.origin.rawValue)] \(f.title)" + (f.scope.map { " (scope: \($0))" } ?? ""))
        }
        lines.append("")
        lines.append("SIDE B FEATURES (\(ledgerB.features.count))")
        for f in ledgerB.features {
            lines.append("- [\(f.origin.rawValue)] \(f.title)" + (f.scope.map { " (scope: \($0))" } ?? ""))
        }
        return lines.joined(separator: "\n")
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
