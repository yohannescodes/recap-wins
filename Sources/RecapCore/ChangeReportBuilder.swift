import Foundation

/// Builds a `ChangeReport` for a head-vs-base change set, entirely offline.
///
/// This is the deterministic core (PRD §5). Given resolved refs, it asks git for
/// the commit list, diff stats, and branch topology, then classifies and
/// aggregates them into the structured report the rest of the tool renders.
public struct ChangeReportBuilder {
    public let git: Git
    public let hotspotLimit: Int
    public let riskThresholds: RiskHeuristics.Thresholds

    public init(
        git: Git,
        hotspotLimit: Int = 5,
        riskThresholds: RiskHeuristics.Thresholds = .init()
    ) {
        self.git = git
        self.hotspotLimit = hotspotLimit
        self.riskThresholds = riskThresholds
    }

    /// Build the report for `base..head`.
    ///
    /// - Parameters:
    ///   - base: base ref as named by the user (default "main").
    ///   - head: head ref as named by the user (default "HEAD").
    public func build(base: String, head: String) throws -> ChangeReport {
        try git.ensureRepository()

        let baseSHA = try git.resolve(base)
        let headSHA = try git.resolve(head)
        let mergeBaseSHA = try git.mergeBase(baseSHA, headSHA)

        let range = ChangeRange(
            base: base, head: head,
            baseSHA: baseSHA, headSHA: headSHA, mergeBaseSHA: mergeBaseSHA
        )

        let rawCommits = try loadCommits(mergeBase: mergeBaseSHA, head: headSHA)
        let files = try loadFileChanges(mergeBase: mergeBaseSHA, head: headSHA)
        let commits = inferBuckets(for: rawCommits, files: files)
        let branches = try loadBranches(mergeBase: mergeBaseSHA, headRef: head)
        let vitals = buildVitals(commits: commits, files: files, branchCount: branches.count)
        let risk = RiskHeuristics.evaluate(files: files, thresholds: riskThresholds)

        return ChangeReport(
            range: range,
            commits: commits,
            files: files,
            branches: branches,
            vitals: vitals,
            riskFlags: risk
        )
    }

    // MARK: - Commits

    /// Field separator unlikely to appear in commit metadata.
    private static let fieldSep = "\u{1f}"   // ASCII Unit Separator
    private static let recordSep = "\u{1e}"  // ASCII Record Separator

    func loadCommits(mergeBase: String, head: String) throws -> [Commit] {
        // %x1f-delimited fields, %x1e-delimited records. Body (%b) last because
        // it may contain newlines; we read everything up to the next %x1e.
        let format = [
            "%H", "%h", "%an", "%ae", "%aI", "%P", "%s", "%b",
        ].joined(separator: Self.fieldSep) + Self.recordSep

        let raw = try git.run([
            "log", "--no-color", "--reverse",
            "--pretty=format:\(format)",
            "\(mergeBase)..\(head)",
        ])

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        var commits: [Commit] = []
        for record in raw.components(separatedBy: Self.recordSep) {
            let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let fields = record.components(separatedBy: Self.fieldSep)
            guard fields.count >= 8 else {
                throw GitError.unexpectedOutput("commit record had \(fields.count) fields, expected 8")
            }
            let sha = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let shortSHA = fields[1]
            let authorName = fields[2]
            let authorEmail = fields[3]
            let dateString = fields[4]
            let parents = fields[5].split(separator: " ")
            let subject = fields[6]
            let body = fields[7]

            let date = isoFormatter.date(from: dateString)
                ?? isoPlain.date(from: dateString)
                ?? Date(timeIntervalSince1970: 0)

            let parsed = CommitParser.parse(subject: subject, body: body)
            let ticket = CommitParser.detectTicket(in: [subject, body])

            commits.append(Commit(
                sha: sha,
                shortSHA: shortSHA,
                authorName: authorName,
                authorEmail: authorEmail,
                date: date,
                subject: subject,
                type: parsed.type,
                scope: parsed.scope,
                breaking: parsed.breaking,
                isMerge: parents.count > 1,
                ticket: ticket
            ))
        }
        return commits
    }

    // MARK: - Files

    func loadFileChanges(mergeBase: String, head: String) throws -> [FileChange] {
        // --numstat gives insertions/deletions/path; --name-status gives the
        // status letter. Run numstat for counts, then enrich with status.
        let numstat = try git.run([
            "diff", "--numstat", "--no-color", "\(mergeBase)..\(head)",
        ])
        let nameStatus = try git.run([
            "diff", "--name-status", "--no-color", "\(mergeBase)..\(head)",
        ])

        // Map path → status letter (first char, e.g. R100 → "R").
        var statusByPath: [String: String] = [:]
        for line in nameStatus.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let statusCol = cols.first, let letter = statusCol.first else { continue }
            // Renames/copies have two paths (old, new); key on the new path.
            let path = cols.count >= 3 ? String(cols[2]) : (cols.count >= 2 ? String(cols[1]) : "")
            if !path.isEmpty { statusByPath[Self.normalizeRenamePath(path)] = String(letter) }
        }

        var files: [FileChange] = []
        for line in numstat.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            // Binary files show "-" for counts; treat as 0.
            let insertions = Int(cols[0]) ?? 0
            let deletions = Int(cols[1]) ?? 0
            // numstat renders renames inline as "old => new" (or with a brace
            // segment "pre/{old => new}/post"); resolve to the new path so the
            // file reads as one renamed entry, not a literal arrow string.
            let path = Self.normalizeRenamePath(String(cols[2]))
            files.append(FileChange(
                path: path,
                insertions: insertions,
                deletions: deletions,
                status: statusByPath[path] ?? "M"
            ))
        }
        return files
    }

    /// Resolve git's inline rename notation to the destination path.
    /// Handles both `old => new` and the braced `pre/{old => new}/post` forms;
    /// returns the input unchanged when there's no rename arrow.
    static func normalizeRenamePath(_ raw: String) -> String {
        guard raw.contains("=>") else { return raw }
        // Braced form: pre/{old => new}/post → pre/new/post.
        if let open = raw.firstIndex(of: "{"), let close = raw.firstIndex(of: "}"), open < close {
            let inside = raw[raw.index(after: open)..<close]
            let newPart = inside.components(separatedBy: "=>").last?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let prefix = raw[raw.startIndex..<open]
            let suffix = raw[raw.index(after: close)...]
            // Collapse any doubled slashes that arise when old/new is empty.
            return (prefix + newPart + suffix)
                .replacingOccurrences(of: "//", with: "/")
        }
        // Simple form: old => new.
        return raw.components(separatedBy: "=>").last?
            .trimmingCharacters(in: .whitespaces) ?? raw
    }

    // MARK: - Branches

    func loadBranches(mergeBase: String, headRef: String) throws -> [BranchInfo] {
        // Local branches whose tip is reachable in base..head, i.e. that
        // contributed commits to this change set (PRD §6 `branch`).
        let headBranch = try? git.currentBranch()

        let raw = try git.run([
            "for-each-ref", "--format=%(refname:short)", "refs/heads",
        ])
        let names = raw.split(separator: "\n").map(String.init)

        var branches: [BranchInfo] = []
        for name in names {
            // Commits in this change set reachable from this branch.
            let count: Int
            do {
                let out = try git.run([
                    "rev-list", "--count", "\(mergeBase)..\(name)",
                ])
                count = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            } catch {
                continue
            }
            let isHead = (name == headBranch) || (name == headRef)
            // Only include branches that actually contributed, plus always the head.
            if count > 0 || isHead {
                branches.append(BranchInfo(name: name, commitCount: count, isHead: isHead))
            }
        }
        // Head branch first, then by contribution descending.
        branches.sort { lhs, rhs in
            if lhs.isHead != rhs.isHead { return lhs.isHead }
            return lhs.commitCount > rhs.commitCount
        }
        return branches
    }

    // MARK: - Inference

    /// Enrich `.other` commits with an inferred bucket from the subject + diff.
    /// Conventional commits are left untouched — only non-prefixed commits get a
    /// guess, recorded in `inferredBucket` (the parsed `type` is never changed).
    func inferBuckets(for commits: [Commit], files: [FileChange]) -> [Commit] {
        let addedSourceFiles = files.contains {
            $0.status == "A" && CommitClassifier.isSourceFile($0.path)
        }
        return commits.map { commit in
            guard commit.type == .other, !commit.isMerge else { return commit }
            var enriched = commit
            enriched.inferredBucket = CommitClassifier.infer(
                subject: commit.subject, addedSourceFiles: addedSourceFiles)
            return enriched
        }
    }

    // MARK: - Vitals

    func buildVitals(commits: [Commit], files: [FileChange], branchCount: Int) -> Vitals {
        // Bucket non-merge commits; merges aren't "work introduced".
        let work = commits.filter { !$0.isMerge }
        var features = 0, fixes = 0, chores = 0
        var inferredCount = 0
        for c in work {
            switch c.effectiveBucket {
            case .feature: features += 1
            case .fix: fixes += 1
            case .chore: chores += 1
            }
            if c.isInferred { inferredCount += 1 }
        }

        let insertions = files.reduce(0) { $0 + $1.insertions }
        let deletions = files.reduce(0) { $0 + $1.deletions }

        // Contributors by (name, email), commit-count descending.
        var byKey: [String: Contributor] = [:]
        var order: [String] = []
        for c in commits where !c.isMerge {
            let key = "\(c.authorEmail.lowercased())"
            if var existing = byKey[key] {
                existing.commitCount += 1
                byKey[key] = existing
            } else {
                byKey[key] = Contributor(name: c.authorName, email: c.authorEmail, commitCount: 1)
                order.append(key)
            }
        }
        let contributors = order.compactMap { byKey[$0] }
            .sorted { $0.commitCount > $1.commitCount }

        let hotspots = files
            .sorted { $0.churn > $1.churn }
            .prefix(hotspotLimit)
            .map { $0 }

        return Vitals(
            features: features,
            fixes: fixes,
            chores: chores,
            filesChanged: files.count,
            insertions: insertions,
            deletions: deletions,
            contributors: contributors,
            branchCount: branchCount,
            hotspots: Array(hotspots),
            inferredCount: inferredCount
        )
    }
}
