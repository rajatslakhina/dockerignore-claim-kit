@testable import DockerignoreClaimKit
import Testing

@Suite("Reading answers")
struct ReaderTests {
    func claims(_ text: String, context: String = "") -> [DockerignoreClaim] {
        DockerignoreClaimChecker().claims(in: text, context: context)
    }

    func summary(_ text: String) -> [String] {
        claims(text).map { "\($0.kind.rawValue) \($0.assertion.rawValue) \($0.subject)" }
    }

    @Test("verbs and phrases", arguments: [
        ("In .dockerignore, `!logs/keep.log` brings back `logs/keep.log` after `logs`.", "path included logs/keep.log"),
        ("In .dockerignore, after `logs` and `!logs/keep.log`, `logs/keep.log` shows up in the image.",
         "path included logs/keep.log"),
        ("In .dockerignore, after `logs` and `!logs/keep.log`, `logs/keep.log` ends up in the image.",
         "path included logs/keep.log"),
        ("In .dockerignore, after `logs` and `!logs/keep.log`, `logs/keep.log` makes it into the image.",
         "path included logs/keep.log"),
        ("In .dockerignore, `logs` leaves out `logs/a.log`.", "path excluded logs/a.log"),
        ("In .dockerignore, `*.log` includes `a.log`.", "path excluded a.log"),
        ("In .dockerignore, `*.log` doesn't include `a/b.log`.", "path included a/b.log"),
        ("In .dockerignore, `/build` excludes `build/a`.", "path excluded build/a"),
        ("In .dockerignore, `doc/*.txt` is anchored to the context root.", "scope rootOnly doc/*.txt"),
        ("In .dockerignore, after `logs` and `!logs/keep.log`, `logs/keep.log` is sent.", "path included logs/keep.log"),
        ("In .dockerignore, after `logs`, `!logs/keep.log` works.", "path included logs/keep.log"),
        ("In .dockerignore, after `logs` and `!logs/keep.log`, `logs/keep.log` appears in the image.",
         "path included logs/keep.log"),
        ("With `logs` and `!logs/keep.log` in .dockerignore, `logs/keep.log` is not excluded.",
         "path included logs/keep.log"),
        ("In .dockerignore, `build` is anchored.", "scope rootOnly build"),
        ("In .dockerignore, after `logs`, `!logs/keep.log` does nothing.", "path excluded logs/keep.log"),
        ("In .dockerignore, `node_modules # deps` excludes `node_modules/x`.", "path excluded node_modules/x")
    ])
    func phrases(_ text: String, _ expected: String) {
        #expect(summary(text) == [expected])
    }

    @Test("what is not read as a claim", arguments: [
        "In .dockerignore, `doc/*.txt` and `a/*.txt` are anchored.",
        "If you use .dockerignore, `*.log` excludes `a.log`.",
        "In .dockerignore, `logs/keep.log` is sent.",
        "In .dockerignore, `!logs/keep.log` works.",
        "With .dockerignore, `!**/keep.txt` brings back `node_modules`.",
        "You should exclude `node_modules` in `.dockerignore`.",
        "Does `.dockerignore` exclude `a.log`?"
    ])
    func quiet(_ text: String) {
        #expect(claims(text).isEmpty)
    }

    @Test("a `!` line of the answer's .dockerignore, named in prose")
    func blockLines() {
        let answer = "```dockerignore\nnode_modules\n!**/keep.txt\n```\n\n`!**/keep.txt` brings back "
            + "`node_modules/pkg/keep.txt`. After that, `!**/keep.txt` works."
        #expect(summary(answer) == ["path included node_modules/pkg/keep.txt"])
        let literal = "```dockerignore\nlogs\n!logs/keep.log\n```\n\n`!logs/keep.log` works."
        #expect(summary(literal) == ["path included logs/keep.log"])
    }

    @Test("an exception named after \"except\"")
    func except() {
        let answer = "```dockerignore\nlogs\n!logs/keep.log\n```\n\nEverything in `logs/` is excluded except "
            + "`logs/keep.log`."
        #expect(summary(answer) == ["path included logs/keep.log"])
        #expect(Lexicon.negationCount(["no", "longer"]) == 1)
        #expect(Lexicon.negationCount(["no", "slash"]) == 0)
    }

    @Test("which code blocks are the build context's .dockerignore")
    func blocks() {
        #expect(RuleBlocks.find(in: AnswerBlocks.split("In `.dockerignore`:\n```dockerignore\n```")).count == 1)
        #expect(RuleBlocks.find(in: AnswerBlocks.split("```\n# .dockerignore\na\n```")).count == 1)
        #expect(RuleBlocks.find(in: AnswerBlocks.split("```\n# app/.dockerignore\na\n```")).isEmpty)
        #expect(RuleBlocks.find(in: AnswerBlocks.split("```\n# .gitignore\na\n```")).isEmpty)
        #expect(RuleBlocks.find(in: AnswerBlocks.split("In `app/.dockerignore`:\n```dockerignore\na\n```")).isEmpty)
        #expect(RuleBlocks.find(in: AnswerBlocks.split("Copy `.dockerignore` to `.gitignore`:\n```\na\n```")).isEmpty)
        #expect(RuleBlocks.find(in: AnswerBlocks.split("In `.dockerignore`:\n```\ndocker build .\n```")).isEmpty)
        #expect(RuleBlocks.find(in: AnswerBlocks.split("In `.dockerignore`:\n```text\na\n```")).count == 1)
        #expect(RuleBlocks.find(in: AnswerBlocks.split("In `.dockerignore`:\n```python\na\n```")).isEmpty)
        #expect(!RuleBlocks.isNested("`./.dockerignore`"))
        #expect(RuleBlocks.lastFileName(in: "no file here") == nil)
        let counter = "This doesn't work in `.dockerignore`:\n```\na # comment\n```"
        #expect(claims(counter).isEmpty)
    }

    @Test("statements about the file itself")
    func statements() {
        #expect(summary("Docker reads a `.dockerignore` in each subdirectory.") == [
            "location nestedFileApplies .dockerignore"
        ])
        #expect(summary("`app/.dockerignore` has no effect on the build.") == [
            "location nestedFileIgnored app/.dockerignore"
        ])
        #expect(claims("If you build from `app/`, `app/.dockerignore` applies.").isEmpty)
        #expect(summary("Excluding `.dockerignore` itself in the file makes the build fail.") == [
            "buildFiles buildFails .dockerignore"
        ])
        #expect(claims("Does a `.dockerignore` in each subdirectory apply?").isEmpty)
    }

    @Test("lines are claims only when the policy says so; context can make an answer about .dockerignore")
    func policyAndContext() {
        let answer = "```dockerignore\na # b\n```"
        #expect(DockerignoreClaimChecker(policy: .lenient).claims(in: answer).isEmpty)
        #expect(claims("`*.log` excludes `a.log`.").isEmpty)
        #expect(summary("`*.log` excludes `a.log`.").isEmpty)
        #expect(claims("`*.log` excludes `a.log`.", context: "My .dockerignore has `*.log`.").count == 1)
        #expect(Clauses.cut([.word("a"), .word("if"), .word("b")]) == [.word("a")])
    }
}
