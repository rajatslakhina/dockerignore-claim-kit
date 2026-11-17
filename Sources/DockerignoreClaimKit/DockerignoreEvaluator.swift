import GitignoreClaimKit

/// Applies Docker's rules to a claim.
struct DockerignoreEvaluator {
    let policy: DockerignorePolicy

    /// The misreadings tried, in order, to name the slip behind a wrong claim, each with the claim it can explain
    /// (`true`: "is excluded", `false`: "is sent", `nil`: either).
    struct Misreading {
        let reading: Reading
        let slip: DockerignoreFinding.Slip
        let explains: Bool?
    }

    static let misreadings = [
        Misreading(reading: .trailingComments, slip: .trailingComment, explains: nil),
        Misreading(reading: .slashlessAnyDepth, slip: .rootRelative, explains: nil),
        Misreading(reading: .excludedParentIsFinal, slip: .exceptionReincludes, explains: true),
        Misreading(reading: .starCrossesSlash, slip: .starStopsAtSlash, explains: true),
        Misreading(reading: .bangNegates, slip: .bangInBracket, explains: nil),
        Misreading(reading: .firstMatchWins, slip: .lastMatchWins, explains: nil),
        Misreading(reading: .ignoreCase, slip: .letterCase, explains: nil)
    ]

    func judge(_ claim: DockerignoreClaim) -> DockerignoreFinding {
        switch claim.kind {
        case .location:
            let outcome: DockerignoreFinding.Outcome = claim.assertion == .nestedFileApplies
                ? .wrong(.nestedIgnoreFile) : .exact
            return DockerignoreFinding(claim: claim, outcome: outcome)
        case .buildFiles:
            let outcome: DockerignoreFinding.Outcome = claim.assertion == .buildFails
                ? .wrong(.buildFilesStillRead) : .exact
            return DockerignoreFinding(claim: claim, outcome: outcome)
        case .line:
            return judgeLine(claim)
        case .scope:
            return judgeScope(claim)
        case .path:
            return judgePath(claim)
        }
    }

    func judgePath(_ claim: DockerignoreClaim) -> DockerignoreFinding {
        // No .dockerignore at all sends everything.
        let rules = claim.rules ?? DockerignoreRules("")
        if let problem = rules.problem {
            return DockerignoreFinding(claim: claim, outcome: .unchecked(Self.describe(problem)))
        }
        let path = claim.subject
        let claimed = claim.assertion == .excluded
        let classic = rules.verdict(path, builder: .classic, reading: [])
        let buildKit = rules.verdict(path, builder: .buildKit, reading: [])
        let builder: DockerBuilder
        if let pinned = policy.builder {
            builder = pinned
        } else if classic.isExcluded == buildKit.isExcluded {
            builder = .classic
        } else {
            let holdsWith: DockerBuilder = classic.isExcluded == claimed ? .classic : .buildKit
            let outcome: DockerignoreFinding.Outcome = policy.reportsCaveats
                ? .caveat(.dependsOnBuilder(holdsWith: holdsWith)) : .exact
            return DockerignoreFinding(claim: claim, outcome: outcome, verdict: classic)
        }
        let verdict = builder == .classic ? classic : buildKit
        guard verdict.isExcluded != claimed else {
            return DockerignoreFinding(claim: claim, outcome: .exact, verdict: verdict)
        }
        let misread = Self.misreadings.lazy.compactMap { misreading -> (DockerignoreFinding.Slip, ContextVerdict)? in
            guard misreading.explains != !claimed else { return nil }
            let other = rules.verdict(path, builder: builder, reading: misreading.reading)
            return other.isExcluded == claimed ? (misreading.slip, other) : nil
        }.first
        if let (slip, other) = misread {
            return DockerignoreFinding(claim: claim, outcome: .wrong(slip), verdict: verdict,
                                       fix: Self.fix(for: slip, line: other.decidingPattern))
        }
        if !claimed, verdict.skippedDirectory != nil,
           rules.patterns.contains(where: { $0.isException && $0.matches(Array(path.unicodeScalars), reading: []) }) {
            return DockerignoreFinding(claim: claim, outcome: .wrong(.skippedDirectory), verdict: verdict,
                                       fix: "!" + path)
        }
        let git = IgnoreRules(rules.text).verdict(for: path).isIgnored
        return DockerignoreFinding(claim: claim, outcome: .wrong(git == claimed ? .gitignoreRules : nil),
                                   verdict: verdict)
    }

    static func describe(_ problem: (line: DockerignorePattern, problem: PatternProblem)) -> String {
        let line = "line \(problem.line.lineNumber) (`\(problem.line.line)`)"
        switch problem.problem {
        case .malformed:
            return "Docker rejects \(line), so `docker build` stops before it sends the context"
        case .unmodelled:
            return "Docker turns \(line) into a regular expression this checker does not reproduce"
        }
    }

    /// A line that does what a wrong claim expected.
    static func fix(for slip: DockerignoreFinding.Slip, line: DockerignorePattern?) -> String? {
        guard let line else { return nil }
        let bang = line.isException ? "!" : ""
        switch slip {
        case .trailingComment, .rootRelative:
            return bang + line.body
        case .starStopsAtSlash:
            return line.body.contains("/*") ? bang + line.body.replacingOccurrences(of: "/*", with: "/**/*") : nil
        case .bangInBracket:
            return bang + line.body.replacingOccurrences(of: "[!", with: "[^")
        default:
            return nil
        }
    }

    func judgeScope(_ claim: DockerignoreClaim) -> DockerignoreFinding {
        guard let pattern = DockerignorePattern(line: claim.subject, lineNumber: 1), pattern.program != nil,
              let sample = Samples.path(for: pattern) else {
            return DockerignoreFinding(claim: claim,
                                       outcome: .unchecked("no sample path could be built for the pattern"))
        }
        let deeper = "sub/" + sample
        let matchesDeeper = pattern.matches(Array(deeper.unicodeScalars), reading: [])
        guard (claim.assertion == .anyDepth) != matchesDeeper else {
            return DockerignoreFinding(claim: claim, outcome: .exact, example: deeper)
        }
        if matchesDeeper {
            let fix = pattern.body.hasPrefix("**/") ? String(pattern.body.dropFirst(3)) : nil
            return DockerignoreFinding(claim: claim, outcome: .wrong(nil), example: deeper, fix: fix)
        }
        return DockerignoreFinding(claim: claim, outcome: .wrong(.rootRelative), example: deeper,
                                   fix: "**/" + pattern.body)
    }

    func judgeLine(_ claim: DockerignoreClaim) -> DockerignoreFinding {
        let intended = DockerignorePattern.withoutTrailingComment(claim.subject)
        let example = DockerignorePattern(line: intended, lineNumber: 1).flatMap(Samples.path)
        return DockerignoreFinding(claim: claim, outcome: .wrong(.trailingComment), example: example, fix: intended)
    }
}

/// A path a pattern matches, for showing what a scope or line claim means.
enum Samples {
    static func path(for pattern: DockerignorePattern) -> String? {
        var body = pattern.body.replacingOccurrences(of: "**/", with: "")
        if body.hasSuffix("/**") { body = String(body.dropLast(2)) + "x" }
        var result = ""
        var characters = ArraySlice(body)
        while let character = characters.popFirst() {
            switch character {
            case "*": if characters.first != "*" { result.append("x") }
            case "?": result.append("x")
            case "\\": if let next = characters.popFirst() { result.append(next) }
            case "[":
                guard let close = characters.firstIndex(of: "]"), let first = characters.first,
                      first != "^" else { return nil }
                result.append(first)
                characters = characters[(close + 1)...]
            default: result.append(character)
            }
        }
        return !result.isEmpty && pattern.matches(Array(result.unicodeScalars), reading: []) ? result : nil
    }
}
