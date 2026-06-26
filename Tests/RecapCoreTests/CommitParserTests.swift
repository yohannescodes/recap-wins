import Testing
@testable import RecapCore

@Suite("Conventional-commit parsing")
struct CommitParserTests {
    @Test("parses type and bucket")
    func basicTypes() {
        #expect(CommitParser.parse(subject: "feat: add login").type == .feat)
        #expect(CommitParser.parse(subject: "fix: null guard").type == .fix)
        #expect(CommitParser.parse(subject: "chore: bump deps").type == .chore)
        #expect(CommitParser.parse(subject: "docs: readme").type == .docs)
    }

    @Test("buckets fold types into feature/fix/chore")
    func buckets() {
        #expect(CommitType.feat.bucket == .feature)
        #expect(CommitType.fix.bucket == .fix)
        #expect(CommitType.refactor.bucket == .chore)
        #expect(CommitType.docs.bucket == .chore)
        #expect(CommitType.other.bucket == .chore)
    }

    @Test("parses scope")
    func scope() {
        let p = CommitParser.parse(subject: "feat(parser): handle scopes")
        #expect(p.type == .feat)
        #expect(p.scope == "parser")
    }

    @Test("detects breaking via bang and footer")
    func breaking() {
        #expect(CommitParser.parse(subject: "feat!: drop v1").breaking == true)
        #expect(CommitParser.parse(subject: "feat(api)!: drop v1").breaking == true)
        #expect(CommitParser.parse(subject: "feat: x", body: "BREAKING CHANGE: gone").breaking == true)
        #expect(CommitParser.parse(subject: "feat: x").breaking == false)
    }

    @Test("non-conventional subjects fall to .other")
    func other() {
        #expect(CommitParser.parse(subject: "WIP messy commit").type == .other)
        #expect(CommitParser.parse(subject: "Merge branch 'main'").type == .other)
        #expect(CommitParser.parse(subject: "fixed a thing").type == .other) // no colon
    }

    @Test("detects ticket references")
    func tickets() {
        #expect(CommitParser.detectTicket(in: ["feat: x (NOV-42)"]) == "NOV-42")
        #expect(CommitParser.detectTicket(in: ["fix: thing #123"]) == "#123")
        #expect(CommitParser.detectTicket(in: ["feat: nothing here"]) == nil)
    }
}
