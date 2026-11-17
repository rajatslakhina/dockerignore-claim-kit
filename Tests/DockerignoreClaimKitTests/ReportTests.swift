@testable import DockerignoreClaimKit
import Testing

@Suite("Reports and wording")
struct ReportTests {
    func finding(_ kind: DockerignoreClaim.Kind, _ assertion: DockerignoreClaim.Assertion,
                 _ outcome: DockerignoreFinding.Outcome, subject: String = "x", verdict: ContextVerdict? = nil,
                 example: String? = nil, fix: String? = nil) -> DockerignoreFinding {
        DockerignoreFinding(claim: DockerignoreClaim(kind: kind, subject: subject, assertion: assertion, sentence: "s"),
                            outcome: outcome, verdict: verdict, example: example, fix: fix)
    }

    @Test("verdicts, summary, note and feedback")
    func report() {
        #expect(DockerignoreReport(findings: []).verdict == .noClaims)
        #expect(DockerignoreReport(findings: []).summary == "no claims about .dockerignore rules")
        #expect(DockerignoreReport(findings: []).note == nil && DockerignoreReport(findings: []).feedback == nil)
        let holds = finding(.location, .nestedFileIgnored, .exact)
        let unchecked = finding(.path, .excluded, .unchecked("no reason"))
        let caveat = finding(.path, .included, .caveat(.dependsOnBuilder(holdsWith: .classic)))
        var wrong = finding(.buildFiles, .buildFails, .wrong(.buildFilesStillRead), subject: "Dockerfile")
        wrong.isRepeated = true
        #expect(DockerignoreReport(findings: [holds]).verdict == .verified)
        #expect(DockerignoreReport(findings: [holds, unchecked]).verdict == .unchecked)
        #expect(DockerignoreReport(findings: [unchecked, caveat]).verdict == .caution)
        let all = DockerignoreReport(findings: [holds, unchecked, caveat, wrong])
        #expect(all.verdict == .wrong)
        #expect(all.summary == "4 claims checked, 1 hold, 1 unchecked, 1 to check, 1 wrong, 1 repeated")
        #expect(DockerignoreReport(findings: [holds]).summary == "1 claim checked, 1 hold")
        #expect(DockerignoreReport(findings: [wrong]).summary == "1 claim checked, 0 hold, 1 wrong, 1 repeated")
        #expect(all.corrections.count == 2 && all.repeatedCount == 1)
        #expect(all.note?.hasPrefix("Dockerignore check: That `x` is sent with the build context holds only") == true)
        #expect(all.note?.hasSuffix("stated again after a correction was asked for.") == true)
        #expect(DockerignoreReport(findings: [caveat]).note?.contains("stated again") == false)
        #expect(all.feedback?.contains("- Listing `Dockerfile` in .dockerignore does not break the build.") == true)
    }

    @Test("every statement and confirmation")
    func wording() {
        let pattern = DockerignorePattern(line: "logs", lineNumber: 1)
        let exception = DockerignorePattern(line: "!logs/a", lineNumber: 2)
        let rows: [(DockerignoreFinding, String)] = [
            (finding(.path, .excluded, .exact), "Right: `x` is left out of the build context."),
            (finding(.path, .included, .exact, verdict: ContextVerdict(isExcluded: false, decidingPattern: nil,
                                                                        skippedDirectory: nil)),
             "Right: `x` is sent: no line matches it."),
            (finding(.path, .included, .exact, subject: "logs/a",
                     verdict: ContextVerdict(isExcluded: false, decidingPattern: exception, skippedDirectory: nil)),
             "Right: `logs/a` is sent: `!logs/a` brings it back."),
            (finding(.scope, .anyDepth, .exact, example: "sub/x"), "Right: `x` matches at any depth (`sub/x` is matched)."),
            (finding(.scope, .rootOnly, .exact), "Right: `x` matches only at the root of the build context."),
            (finding(.line, .takesEffect, .exact), "Right: `x` works as a pattern."),
            (finding(.location, .nestedFileApplies, .exact), "Right: A .dockerignore in a subdirectory applies there."),
            (finding(.buildFiles, .buildWorks, .exact),
             "Right: Listing `x` in .dockerignore does not break the build."),
            (finding(.path, .excluded, .caveat(.dependsOnBuilder(holdsWith: .classic))),
             "That `x` is left out of the build context holds only with the classic builder; BuildKit searches the "
                + "excluded directory above it and gives the opposite result."),
            (finding(.path, .excluded, .unchecked("a reason")), "Not checked: a reason."),
            (finding(.path, .included, .wrong(.skippedDirectory), subject: "logs/a",
                     verdict: ContextVerdict(isExcluded: true, decidingPattern: pattern, skippedDirectory: "logs/"),
                     fix: "!logs/a"),
             "`logs/a` is left out: `logs` excludes its directory `logs/`, so the claim that it is sent is wrong. The "
                + "classic builder searches an excluded directory only for `!` lines whose text starts with that "
                + "directory's path, so a wildcard exception cannot reach inside it. Add `!logs/a`, which names the "
                + "path literally, so the builder searches the directory."),
            (finding(.path, .excluded, .wrong(nil), subject: "logs",
                     verdict: ContextVerdict(isExcluded: false, decidingPattern: nil, skippedDirectory: nil)),
             "`logs` is sent: no line matches it, so the claim that it is left out is wrong."),
            (finding(.path, .included, .wrong(.lastMatchWins), subject: "logs",
                     verdict: ContextVerdict(isExcluded: true, decidingPattern: pattern, skippedDirectory: nil)),
             "`logs` is left out by `logs`, so the claim that it is sent is wrong. When several lines match a path, "
                + "the last one decides."),
            (finding(.scope, .anyDepth, .wrong(.rootRelative), example: "sub/x", fix: "**/x"),
             "`x` does not match at any depth (`sub/x` is not matched). Docker matches every pattern from the root of "
                + "the build context; unlike .gitignore, a pattern with no slash does not match in subdirectories. "
                + "`**/x` does what the answer expects."),
            (finding(.scope, .rootOnly, .wrong(nil)), "`x` matches below the root too."),
            (finding(.scope, .anyDepth, .wrong(nil)), "`x` does not match at any depth."),
            (finding(.line, .takesEffect, .wrong(.trailingComment), example: "x", fix: "x"),
             "`x` does not exclude `x`. Docker reads `#` as a comment only at the start of a line, so the comment is "
                + "part of the pattern. Put `x` on its own line and the comment on the line above."),
            (finding(.line, .takesEffect, .wrong(nil)), "`x` does not exclude what it was written for."),
            (finding(.location, .nestedFileApplies, .wrong(nil)),
             "A .dockerignore in a subdirectory has no effect unless that folder is the build context."),
            (finding(.location, .nestedFileApplies, .caveat(.onlyIfBuildContext)),
             "A .dockerignore in a subdirectory applies only when that folder is the build context (`docker build "
                + "services/api`, or a compose `build:` pointing at it); building from above it, Docker reads only "
                + "the .dockerignore at the root of the context.")
        ]
        for (finding, expected) in rows {
            #expect(finding.explanation == expected)
        }
        #expect(finding(.location, .nestedFileIgnored, .exact).statement
            == "Docker reads only the .dockerignore at the root of the build context")
        #expect(finding(.buildFiles, .buildFails, .exact).statement == "Listing `x` in .dockerignore breaks the build")
        #expect(finding(.path, .included, .caveat(.dependsOnBuilder(holdsWith: .buildKit))).explanation
            .contains("holds only with BuildKit; the classic builder skips"))
        for slip in DockerignoreFinding.Slip.allCases {
            #expect(DockerignoreFinding.reasons[slip] != nil, "\(slip)")
        }
    }
}
