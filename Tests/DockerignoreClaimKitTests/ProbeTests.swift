@testable import DockerignoreClaimKit
import Testing

/// Answers written the way assistants write them, checked before tagging: correct ones must stay quiet or verified,
/// wrong ones must be caught, and text about anything else must make no claim at all.
@Suite("Probe answers")
struct ProbeTests {
    static let otherDomains = [
        "`[a-z]+` matches `abc`.",
        "`.*` matches `anything`.",
        "`compactMap` ignores `nil` values.",
        "`~1.2` matches `1.2.5`.",
        "`Set` excludes `duplicates`.",
        "The glob `src/*.ts` matches `src/a/b.ts`.",
        "`filter` keeps `even` numbers and excludes `odd` ones.",
        "`NSPredicate(format:)` with `LIKE` matches `a*`.",
        "The route `/users/:id` matches `/users/42`.",
        "`COPY . .` copies `package.json` into the image.",
        "`docker build -t app .` sends the current directory as the build context.",
        "`EXPOSE 8080` does not publish the port.",
        "In `.gitignore`, `*.log` ignores `logs/a.log`.",
        "`node_modules` in `.gitignore` matches `app/node_modules` too.",
        "Your `.npmignore` excludes `test/` from the package.",
        "The linter will ignore files in `dist`, and `*.min.js` matches `dist/app.min.js`."
    ]

    @Test("sentences from other domains make no claim", arguments: otherDomains)
    func otherDomain(_ sentence: String) {
        #expect(DockerignoreClaimChecker().check(sentence).verdict == .noClaims)
    }

    static let gitignoreAnswers = [
        "Add this to `.gitignore`:\n\n```gitignore\nnode_modules\n*.log\n```\n\n`*.log` matches `logs/a.log`.",
        "```\n# .gitignore\nbuild/\n```\nThis ignores `app/build/out.o` as well.",
        "Your `.gitignore` has `logs/` and `!logs/keep.log`, so `logs/keep.log` stays ignored."
    ]

    @Test("answers about .gitignore make no claim", arguments: gitignoreAnswers)
    func gitignoreOnly(_ answer: String) {
        #expect(DockerignoreClaimChecker().check(answer).verdict == .noClaims)
    }

    @Test("in an answer that shows both files, only the .dockerignore is judged")
    func mixed() {
        let answer = """
        Your `.gitignore`:

        ```gitignore
        *.log
        ```

        And your `.dockerignore`:

        ```
        *.log
        node_modules # deps
        ```

        `*.log` matches `logs/a.log`. In the build context, `*.log` excludes `logs/b.log` too.
        """
        let report = DockerignoreClaimChecker().check(answer)
        #expect(report.findings.map(\.claim.subject) == ["node_modules # deps", "logs/b.log"])
        #expect(report.findings.allSatisfy { $0.severity == .wrong })
    }

    @Test("a later turn that names no ignore file stays quiet unless it repeats a flagged claim")
    func laterTurns() async {
        let ledger = DockerignoreLedger()
        let first = await ledger.review("`node_modules` excludes `app/node_modules/x.js`.",
                                        context: "What does my .dockerignore exclude?")
        #expect(first.verdict == .wrong)
        let unrelated = await ledger.review("`[a-z]+` matches `abc`.", context: "What does this regex match?")
        #expect(unrelated.verdict == .noClaims)
        #expect(await ledger.isAboutDockerignore == false)
        let repeated = await ledger.review("Yes, `node_modules` excludes `app/node_modules/x.js`.")
        #expect(repeated.verdict == .wrong)
        #expect(repeated.repeatedCount == 1)
        let stats = await ledger.statistics
        #expect(stats.reviews == 3 && stats.flagged == 2 && stats.repeated == 1)
        await ledger.forget()
        let fresh = await ledger.review("Yes, `node_modules` excludes `app/node_modules/x.js`.")
        #expect(fresh.verdict == .noClaims)
    }

    static let correct = [
        "Add this to `.dockerignore`:\n\n```\n**/node_modules\n*.log\n# local secrets\n.env\n```\n\n"
            + "`**/node_modules` excludes `packages/api/node_modules/react/index.js`, while `*.log` only matches at "
            + "the root of the build context, so `logs/app.log` is still sent.",
        "Docker reads only the `.dockerignore` at the root of the build context, not `services/api/.dockerignore`.",
        "In `.dockerignore`, `node_modules` followed by `!node_modules/pkg/keep.txt` sends `node_modules/pkg/keep.txt` "
            + "and leaves out `node_modules/pkg/other.txt`.",
        "```dockerignore\n*\n!src\n!package.json\n```\n\nThis sends only `src/index.ts` and `package.json`; "
            + "`README.md` is left out.",
        "Is `node_modules` excluded by `.dockerignore`?",
        "A `.dockerignore` keeps the build context small. Use `**/node_modules` rather than `node_modules` in a "
            + "monorepo.",
        "With `.dockerignore`:\n\n```\n.git\n**/*.pyc\n__pycache__\n```\n\n`app/__pycache__/x.pyc` is excluded and "
            + "`.git/config` is left out of the context.",
        "In `.dockerignore`, `**/*.md` matches `docs/guide.md` at any depth.",
        "Listing the `Dockerfile` in `.dockerignore` does not break the build; `docker build` still reads it.",
        "In `.dockerignore`, `*.txt` matches `notes.txt` but not `docs/notes.txt`.",
        "Unlike `.gitignore`, a `.dockerignore` pattern like `build` only matches at the root of the context.",
        "```dockerignore\nlogs\n!logs/keep.log\n```\n\nDocker sends `logs/keep.log` and leaves out `logs/a.log`.",
        "Your `.dockerignore`:\n\n```\nsecrets/*.pem\n```\n\nThis leaves out `secrets/server.pem` but not "
            + "`secrets/old/key.pem`.",
        "To check, run `docker build --no-cache .` and list `/ctx` in the image; `.dockerignore` decides what is sent."
    ]

    @Test("correct answers are not flagged", arguments: correct)
    func correctAnswer(_ answer: String) {
        let report = DockerignoreClaimChecker().check(answer)
        #expect(report.flagged.isEmpty, "\(report.corrections)")
    }

    static let wrong: [(String, DockerignoreFinding.Slip?)] = [
        ("Add this to `.dockerignore`:\n\n```\nnode_modules\n```\n\nThis excludes `packages/api/node_modules/x.js`.",
         .rootRelative),
        ("In `.dockerignore`, `*.log` matches log files at any depth.", .rootRelative),
        ("```dockerignore\n.env   # local secrets\n```", .trailingComment),
        ("Put a `.dockerignore` in each service folder, for example `services/api/.dockerignore`.", .nestedIgnoreFile),
        ("Don't list the `Dockerfile` in `.dockerignore`, or `docker build` fails because it can't find it.",
         .buildFilesStillRead),
        ("With this `.dockerignore`:\n\n```\nlogs\n!logs/keep.log\n```\n\n`logs/keep.log` stays excluded.",
         .exceptionReincludes),
        ("The `.dockerignore` pattern `[!a]*.txt` excludes `b.txt`.", .bangInBracket),
        ("In a `.dockerignore`, `README.md` also excludes `readme.md`.", .letterCase),
        ("`.dockerignore`:\n\n```\n!src/keep.go\nsrc\n```\n\n`src/keep.go` is still sent.", .lastMatchWins),
        ("In .dockerignore, `doc/*.txt` excludes `doc/server/arch.txt`.", .starStopsAtSlash)
    ]

    @Test("wrong answers are caught with their slip", arguments: wrong)
    func wrongAnswer(_ answer: String, _ slip: DockerignoreFinding.Slip?) {
        let report = DockerignoreClaimChecker().check(answer)
        #expect(report.verdict == .wrong)
        #expect(report.flagged.first?.outcome == .wrong(slip), "\(report.corrections)")
    }
}
