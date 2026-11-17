import DockerignoreClaimKit

enum Scenarios {
    static func gitignoreHabits() {
        scenario(1, "A .dockerignore written like a .gitignore")
        let wrong = """
        Add this to your `.dockerignore`:

        ```
        node_modules
        *.log
        .env   # local secrets
        ```

        This excludes `node_modules` in every package, so `packages/api/node_modules/react/index.js` is never \
        sent, and `*.log` matches log files at any depth.
        """
        show("answer", DockerignoreClaimChecker().check(wrong))
        let rules = DockerignoreRules("node_modules\n*.log\n.env   # local secrets\n")
        let paths = ["node_modules/react/index.js", "packages/api/node_modules/react/index.js", "logs/app.log", ".env"]
        for path in paths {
            explain(rules, path)
        }
        let right = """
        Docker matches every pattern from the root of the build context, so say where:

        ```dockerignore
        **/node_modules
        **/*.log
        # local secrets
        .env
        ```

        Now `packages/api/node_modules/react/index.js` and `logs/app.log` are left out, and so is `.env`.
        """
        show("rewrite", DockerignoreClaimChecker().check(right))
    }

    static func sameLines() {
        scenario(2, "The same lines, read by git and by Docker")
        let text = "node_modules\n*.log\nlogs\n!logs/keep.log\n"
        print("   lines: node_modules, *.log, logs, !logs/keep.log")
        for path in ["app/node_modules/x.js", "app/debug.log", "logs/keep.log"] {
            compare(text, path)
        }
        let wrong = """
        With this `.dockerignore`:

        ```
        logs
        !logs/keep.log
        ```

        `logs/keep.log` stays excluded, because nothing below an excluded directory can be re-included.
        """
        show("answer", DockerignoreClaimChecker().check(wrong))
    }

    static func builders() {
        scenario(3, "A wildcard exception inside an excluded folder")
        let answer = """
        In `.dockerignore`, `!**/keep.txt` brings back `node_modules/pkg/keep.txt` after `node_modules`.
        """
        show("builder unknown", DockerignoreClaimChecker().check(answer))
        show("classic builder", DockerignoreClaimChecker(policy: .classic).check(answer))
        show("BuildKit", DockerignoreClaimChecker(policy: .buildKit).check(answer))
        let rules = DockerignoreRules("node_modules\n!**/keep.txt\n")
        explain(rules, "node_modules/pkg/keep.txt", builder: .classic)
        explain(rules, "node_modules/pkg/keep.txt", builder: .buildKit)
        let fixed = DockerignoreRules("node_modules\n!node_modules/pkg/keep.txt\n")
        explain(fixed, "node_modules/pkg/keep.txt", builder: .classic)
    }

    static func allowList() {
        scenario(4, "An allow list")
        let answer = """
        ```dockerignore
        *
        !src
        !package.json
        ```

        This sends only `src/index.ts` and `package.json`; `README.md` is left out, and so is `docs/guide.md`.
        """
        show("answer", DockerignoreClaimChecker().check(answer))
        let rules = DockerignoreRules("*\n!src\n!package.json\n")
        for path in ["src/index.ts", "src/lib/util.ts", "package.json", "README.md", "Dockerfile"] {
            explain(rules, path)
        }
    }
}
