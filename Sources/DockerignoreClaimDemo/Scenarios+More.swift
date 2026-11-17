import DockerignoreClaimKit

extension Scenarios {
    static func fileMyths() {
        scenario(5, "Where the file lives, and listing the Dockerfile")
        let wrong = """
        Put a `.dockerignore` in each service folder, for example `services/api/.dockerignore`. Don't list the \
        `Dockerfile` in `.dockerignore`, or `docker build` fails because it can't find it.
        """
        show("answer", DockerignoreClaimChecker().check(wrong))
        let right = """
        Docker reads only the `.dockerignore` at the root of the build context, not `services/api/.dockerignore`. \
        Listing the `Dockerfile` in `.dockerignore` does not break the build; `docker build` still reads it.
        """
        show("rewrite", DockerignoreClaimChecker().check(right))
        explain(DockerignoreRules("Dockerfile\n.dockerignore\n"), "Dockerfile")
    }

    static func shellHabits() {
        scenario(6, "Shell-glob habits: [!a], letter case, a star across folders")
        let wrong = """
        In `.dockerignore`, the pattern `[!a]*.txt` excludes `b.txt`. `README.md` also excludes `readme.md` on \
        macOS, and `doc/*.txt` excludes `doc/server/arch.txt`.
        """
        show("answer", DockerignoreClaimChecker().check(wrong))
        explain(DockerignoreRules("[!a]*.txt\n"), "!x.txt")
        explain(DockerignoreRules("[!a]*.txt\n"), "a.txt")
    }

    static func problems() {
        scenario(7, "A line Docker rejects")
        let answer = """
        ```dockerignore
        [a
        node_modules
        ```

        This excludes `node_modules/x.js`.
        """
        show("answer", DockerignoreClaimChecker().check(answer))
        if let problem = DockerignoreRules("[a\nnode_modules\n").problem {
            print("   line \(problem.line.lineNumber) `\(problem.line.line)`: \(problem.problem)")
        }
    }

    static func conversation() async {
        scenario(8, "A conversation: the same mistake after a correction")
        let ledger = DockerignoreLedger()
        let question = "Does my .dockerignore keep node_modules out of every package?"
        let first = await ledger.review("Yes: `node_modules` excludes `packages/web/node_modules/vite/index.js`.",
                                        context: question)
        show("turn 1", first)
        print("   feedback sent: \(first.feedback?.split(separator: "\n").count ?? 0) lines")
        let unrelated = await ledger.review("`[a-z]+` matches `abc`.", context: "What does this regex match?")
        show("turn 2, about a regex", unrelated)
        let again = await ledger.review(
            "You're right, but `node_modules` excludes `packages/web/node_modules/vite/index.js`.")
        show("turn 3", again)
        let stats = await ledger.statistics
        print("   ledger: \(stats.reviews) reviews, \(stats.claims) claims, \(stats.flagged) flagged, "
              + "\(stats.repeated) repeated")
    }
}
