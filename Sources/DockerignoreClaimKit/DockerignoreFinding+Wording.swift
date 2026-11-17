extension DockerignoreFinding {
    /// One or two sentences for the person reading the answer.
    public var explanation: String {
        switch outcome {
        case .exact:
            return confirmation
        case .caveat(.dependsOnBuilder(let holdsWith)):
            let other: DockerBuilder = holdsWith == .classic ? .buildKit : .classic
            return "That \(statement) holds only with \(Self.name(holdsWith)); \(Self.name(other)) "
                + (holdsWith == .classic ? "searches" : "skips")
                + " the excluded directory above it and gives the opposite result."
        case .caveat(.onlyIfBuildContext):
            return "A .dockerignore in a subdirectory applies only when that folder is the build context (`docker "
                + "build services/api`, or a compose `build:` pointing at it); building from above it, Docker reads "
                + "only the .dockerignore at the root of the context."
        case .unchecked(let reason):
            return "Not checked: \(reason)."
        case .wrong(let slip):
            return [correction, slip.flatMap { Self.reasons[$0] }, fix.map(advice)].compactMap { $0 }
                .joined(separator: " ")
        }
    }

    static func name(_ builder: DockerBuilder) -> String {
        builder == .classic ? "the classic builder" : "BuildKit"
    }

    /// The claim in words: "`logs/keep.log` is sent".
    var statement: String {
        switch claim.assertion {
        case .excluded: "`\(claim.subject)` is left out of the build context"
        case .included: "`\(claim.subject)` is sent with the build context"
        case .anyDepth: "`\(claim.subject)` matches at any depth"
        case .rootOnly: "`\(claim.subject)` matches only at the root of the build context"
        case .takesEffect: "`\(claim.subject)` works as a pattern"
        case .nestedFileApplies: "A .dockerignore in a subdirectory applies there"
        case .nestedFileIgnored: "Docker reads only the .dockerignore at the root of the build context"
        case .buildFails: "Listing `\(claim.subject)` in .dockerignore breaks the build"
        case .buildWorks: "Listing `\(claim.subject)` in .dockerignore does not break the build"
        }
    }

    var confirmation: String {
        switch claim.kind {
        case .path: "Right: \(truth)."
        case .scope:
            "Right: \(statement)"
                + (example.map { " (`\($0)` is \(claim.assertion == .anyDepth ? "" : "not ")matched)" } ?? "") + "."
        case .line, .location, .buildFiles: "Right: \(statement)."
        }
    }

    /// What Docker does with the claim's path, and which line decides it.
    var truth: String {
        guard let verdict else { return statement }
        let path = "`\(claim.subject)`"
        guard let line = verdict.decidingPattern else { return "\(path) is sent: no line matches it" }
        if let directory = verdict.skippedDirectory {
            return "\(path) is left out: `\(line.line)` excludes its directory `\(directory)`"
        }
        return line.isException ? "\(path) is sent: `\(line.line)` brings it back"
            : "\(path) is left out by `\(line.line)`"
    }

    var correction: String {
        switch claim.kind {
        case .path:
            let said = claim.assertion == .excluded ? "left out" : "sent"
            return "\(truth), so the claim that it is \(said) is wrong."
        case .scope:
            let shown = example.map { " (`\($0)` is \(claim.assertion == .anyDepth ? "not " : "")matched)" } ?? ""
            return claim.assertion == .anyDepth
                ? "`\(claim.subject)` does not match at any depth\(shown)."
                : "`\(claim.subject)` matches below the root too\(shown)."
        case .line:
            return "`\(claim.subject)` does not exclude " + (example.map { "`\($0)`." } ?? "what it was written for.")
        case .location:
            return "A .dockerignore in a subdirectory has no effect unless that folder is the build context."
        case .buildFiles:
            return "Listing `\(claim.subject)` in .dockerignore does not break the build."
        }
    }

    static let reasons: [Slip: String] = [
        .trailingComment:
            "Docker reads `#` as a comment only at the start of a line, so the comment is part of the pattern.",
        .rootRelative: "Docker matches every pattern from the root of the build context; unlike .gitignore, a "
            + "pattern with no slash does not match in subdirectories.",
        .exceptionReincludes: "Unlike git, Docker can bring back a path below an excluded directory when an `!` "
            + "line names it.",
        .starStopsAtSlash: "`*` does not match `/`; `**` does.",
        .bangInBracket: "In .dockerignore `!` inside brackets is an ordinary character; `[^...]` negates.",
        .lastMatchWins: "When several lines match a path, the last one decides.",
        .letterCase: "Docker compares names exactly, so letter case matters even on macOS.",
        .skippedDirectory: "The classic builder searches an excluded directory only for `!` lines whose text "
            + "starts with that directory's path, so a wildcard exception cannot reach inside it.",
        .gitignoreRules: "That is how .gitignore reads this file; Docker's rules differ.",
        .buildFilesStillRead: "Docker still reads the Dockerfile and .dockerignore; listing them only keeps them "
            + "out of what `COPY` and `ADD` can see."
    ]

    func advice(_ fix: String) -> String {
        switch outcome {
        case .wrong(.trailingComment?):
            "Put `\(fix)` on its own line and the comment on the line above."
        case .wrong(.skippedDirectory?):
            "Add `\(fix)`, which names the path literally, so the builder searches the directory."
        default:
            "`\(fix)` does what the answer expects."
        }
    }
}
