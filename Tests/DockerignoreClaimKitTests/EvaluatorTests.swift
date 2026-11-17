@testable import DockerignoreClaimKit
import Testing

@Suite("Judging claims")
struct EvaluatorTests {
    func path(_ subject: String, _ assertion: DockerignoreClaim.Assertion, _ rules: String?) -> DockerignoreClaim {
        DockerignoreClaim(kind: .path, subject: subject, assertion: assertion, sentence: "s",
                          source: .block(1), rules: rules.map(DockerignoreRules.init))
    }

    func judge(_ claim: DockerignoreClaim, _ policy: DockerignorePolicy = .standard) -> DockerignoreFinding {
        DockerignoreClaimChecker(policy: policy).judge(claim)
    }

    @Test("with no .dockerignore everything is sent")
    func noRules() {
        #expect(judge(path("a", .included, nil)).outcome == .exact)
        #expect(judge(path("a", .excluded, nil)).outcome == .wrong(nil))
    }

    @Test("a file Docker rejects, or one not modelled, is not checked")
    func problems() {
        let malformed = judge(path("a", .excluded, "[a\n"))
        #expect(malformed.outcome == .unchecked("Docker rejects line 1 (`[a`), so `docker build` stops before it sends the context"))
        let unmodelled = judge(path("a", .excluded, "[a*]\n"))
        #expect(unmodelled.outcome == .unchecked(
            "Docker turns line 1 (`[a*]`) into a regular expression this checker does not reproduce"))
    }

    @Test("where the builders disagree, the claim is a caveat unless the policy names the builder")
    func builders() {
        let rules = "node_modules\n!**/keep.txt\n"
        let kept = path("node_modules/pkg/keep.txt", .included, rules)
        #expect(judge(kept).outcome == .caveat(.dependsOnBuilder(holdsWith: .buildKit)))
        #expect(judge(path("node_modules/pkg/keep.txt", .excluded, rules)).outcome
            == .caveat(.dependsOnBuilder(holdsWith: .classic)))
        #expect(judge(kept, .lenient).outcome == .exact)
        #expect(judge(kept, .buildKit).outcome == .exact)
        let classic = judge(kept, .classic)
        #expect(classic.outcome == .wrong(.skippedDirectory))
        #expect(classic.fix == "!node_modules/pkg/keep.txt")
        #expect(classic.verdict?.skippedDirectory == "node_modules/")
    }

    @Test("slips found by re-reading the file")
    func slips() {
        let comment = judge(path("node_modules/x", .excluded, "node_modules # deps\n"))
        #expect(comment.outcome == .wrong(.trailingComment) && comment.fix == "node_modules")
        let exception = judge(path("a/b", .included, "a\n!a/b # keep\n"))
        #expect(exception.outcome == .wrong(.trailingComment) && exception.fix == "!a/b")
        let crossing = judge(path("a/b", .excluded, "a*b\n"))
        #expect(crossing.outcome == .wrong(.starStopsAtSlash) && crossing.fix == nil)
        let order = judge(path("README.md", .included, "!README.md\n*.md\n"))
        #expect(order.outcome == .wrong(.lastMatchWins) && order.fix == nil)
        let git = judge(path("logs", .included, "logs/\n"))
        #expect(git.outcome == .wrong(.gitignoreRules))
        #expect(judge(path("b", .excluded, "a\n")).outcome == .wrong(nil))
        #expect(DockerignoreEvaluator.fix(for: .rootRelative, line: nil) == nil)
    }

    func scope(_ pattern: String, _ assertion: DockerignoreClaim.Assertion) -> DockerignoreFinding {
        judge(DockerignoreClaim(kind: .scope, subject: pattern, assertion: assertion, sentence: "s",
                                source: .sentence([pattern])))
    }

    @Test("scope claims")
    func scopes() {
        #expect(scope("*.log", .rootOnly).outcome == .exact)
        let deep = scope("[ab].txt", .anyDepth)
        #expect(deep.outcome == .wrong(.rootRelative) && deep.fix == "**/[ab].txt" && deep.example == "sub/a.txt")
        let root = scope("**/*.log", .rootOnly)
        #expect(root.outcome == .wrong(nil) && root.fix == "*.log")
        let suffix = scope("**foo", .rootOnly)
        #expect(suffix.outcome == .wrong(nil) && suffix.fix == nil && suffix.example == "sub/xfoo")
        #expect(scope("[^a]", .anyDepth).outcome == .unchecked("no sample path could be built for the pattern"))
        #expect(scope("[a*]", .anyDepth).outcome == .unchecked("no sample path could be built for the pattern"))
        #expect(scope("a\\*b?", .rootOnly).example == "sub/a*bx")
        #expect(scope("doc/**", .rootOnly).example == "sub/doc/x")
    }

    @Test("lines, locations and build files")
    func statements() {
        let line = judge(DockerignoreClaim(kind: .line, subject: ".env  # secrets", assertion: .takesEffect,
                                           sentence: "s", isExplicit: false))
        #expect(line.outcome == .wrong(.trailingComment) && line.fix == ".env" && line.example == ".env")
        let odd = judge(DockerignoreClaim(kind: .line, subject: "[^a] # x", assertion: .takesEffect, sentence: "s"))
        #expect(odd.example == nil)
        let cases: [(DockerignoreClaim.Kind, DockerignoreClaim.Assertion, DockerignoreFinding.Outcome)] = [
            (.location, .nestedFileApplies, .caveat(.onlyIfBuildContext)), (.location, .nestedFileIgnored, .exact),
            (.buildFiles, .buildFails, .wrong(.buildFilesStillRead)), (.buildFiles, .buildWorks, .exact)
        ]
        for (kind, assertion, outcome) in cases {
            #expect(judge(DockerignoreClaim(kind: kind, subject: "x", assertion: assertion, sentence: "s")).outcome
                == outcome)
        }
    }
}
