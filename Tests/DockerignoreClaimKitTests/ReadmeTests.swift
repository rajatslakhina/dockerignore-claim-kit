@testable import DockerignoreClaimKit
import Testing

@Suite("README examples")
struct ReadmeTests {
    @Test("the usage example returns what the README says")
    func usage() async {
        let answer = "Add this to your `.dockerignore`:\n\n```\nnode_modules\n.env   # local secrets\n```\n\n"
            + "This excludes `node_modules` in every package, so `packages/api/node_modules/x.js` is never sent."
        let report = DockerignoreClaimChecker().check(answer)
        #expect(report.verdict == .wrong)
        #expect(report.summary == "2 claims checked, 0 hold, 2 wrong")
        #expect(report.note?.hasPrefix("Dockerignore check: `.env   # local secrets` does not exclude `.env`.") == true)
        #expect(report.feedback != nil)
        #expect(report.findings.map(\.fix) == [".env", "**/node_modules"])
        #expect(report.findings.map(\.outcome) == [.wrong(.trailingComment), .wrong(.rootRelative)])

        let rules = DockerignoreRules("node_modules\n!**/keep.txt\n")
        #expect(rules.verdict(for: "node_modules/pkg/keep.txt", builder: .classic).isExcluded)
        #expect(rules.verdict(for: "node_modules/pkg/keep.txt", builder: .classic).skippedDirectory == "node_modules/")
        #expect(!rules.verdict(for: "node_modules/pkg/keep.txt", builder: .buildKit).isExcluded)

        let checker = DockerignoreClaimChecker()
        #expect(checker.check("`*.log` matches `logs/a.log`.").verdict == .noClaims)
        #expect(checker.check("`*.log` matches `logs/a.log`.", context: "Is my .dockerignore right?").verdict == .wrong)

        let ledger = DockerignoreLedger()
        _ = await ledger.review("`node_modules` excludes `app/node_modules/x.js`.", context: "My .dockerignore?")
        let again = await ledger.review("Yes, `node_modules` excludes `app/node_modules/x.js`.")
        #expect(again.repeatedCount == 1)
    }
}
