import Testing
@testable import RecapCore

@Suite("Commit classifier (inference for non-conventional commits)")
struct CommitClassifierTests {
    @Test("feature verbs infer .feature")
    func featureVerbs() {
        #expect(CommitClassifier.bucketFromSubject("Ship Ledgerly New Face") == .feature)
        #expect(CommitClassifier.bucketFromSubject("Add CSV export") == .feature)
        #expect(CommitClassifier.bucketFromSubject("Implement onboarding flow") == .feature)
        #expect(CommitClassifier.bucketFromSubject("Introduce dark mode") == .feature)
    }

    @Test("fix verbs infer .fix and beat feature verbs")
    func fixVerbs() {
        #expect(CommitClassifier.bucketFromSubject("Fix crash on launch") == .fix)
        #expect(CommitClassifier.bucketFromSubject("Resolve null pointer") == .fix)
        // "fix" wins even if a feature verb is also present.
        #expect(CommitClassifier.bucketFromSubject("Fix the new add-account screen") == .fix)
    }

    @Test("chore verbs infer .chore")
    func choreVerbs() {
        #expect(CommitClassifier.bucketFromSubject("Bump marketing version 1.7 → 2.0") == .chore)
        #expect(CommitClassifier.bucketFromSubject("Rename Manual Entries to Assets") == .chore)
        #expect(CommitClassifier.bucketFromSubject("Refactor the view model") == .chore)
        #expect(CommitClassifier.bucketFromSubject("Gate snapshot rebuild behind DEBUG") == .chore)
    }

    @Test("add tests/docs reads as chore, not feature")
    func addTestsIsChore() {
        #expect(CommitClassifier.bucketFromSubject("Add tests for the parser") == .chore)
        #expect(CommitClassifier.bucketFromSubject("Add docs for the API") == .chore)
    }

    @Test("no recognizable verb yields nil from subject")
    func noVerb() {
        #expect(CommitClassifier.bucketFromSubject("WIP") == .chore)   // wip is a chore verb
        #expect(CommitClassifier.bucketFromSubject("Stuff and things") == nil)
    }

    @Test("infer falls back to feature when new source files were added")
    func fileEvidence() {
        // Subject has no verb, but the change set added source files.
        #expect(CommitClassifier.infer(subject: "Misc", addedSourceFiles: true) == .feature)
        // No verb and no new source → no confident guess.
        #expect(CommitClassifier.infer(subject: "Misc", addedSourceFiles: false) == nil)
    }

    @Test("subject keyword wins over file evidence")
    func subjectWinsOverFiles() {
        // A clear chore verb stays a chore even if source files were added.
        #expect(CommitClassifier.infer(subject: "Bump deps", addedSourceFiles: true) == .chore)
    }
}
