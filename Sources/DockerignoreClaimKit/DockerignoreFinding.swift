/// What a claim about .dockerignore rules turned out to be once Docker's rules were applied.
public struct DockerignoreFinding: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case exact
        /// Holds, with something a reader should know.
        case caveat(Caveat)
        case wrong(Slip?)
        /// Could not be checked, and why.
        case unchecked(String)
    }

    public enum Caveat: Sendable, Hashable {
        /// Holds only with this builder: the other one searches (or skips) an excluded directory differently.
        case dependsOnBuilder(holdsWith: DockerBuilder)
        /// A .dockerignore in a subdirectory applies only when that folder is the build context
        /// (`docker build services/api`); building from above it, Docker reads only the context root's file.
        case onlyIfBuildContext
    }

    /// A recognisable mistake behind a wrong claim.
    public enum Slip: String, Sendable, Hashable, CaseIterable {
        /// `node_modules  # deps` read as a pattern and a comment: `#` starts a comment only at the start of a line.
        case trailingComment
        /// `node_modules` or `*.log` read as matching at every level, as in .gitignore: Docker matches patterns
        /// from the root of the build context.
        case rootRelative
        /// An exception read as unable to bring back a path below an excluded directory, as in git: Docker brings
        /// it back.
        case exceptionReincludes
        /// `doc/*.txt` read as matching `doc/a/b.txt`: `*` does not cross `/`.
        case starStopsAtSlash
        /// `[!a]` read as "not `a`": in .dockerignore `!` inside brackets is a plain character; `[^a]` negates.
        case bangInBracket
        /// An earlier line read as deciding: the last matching line wins.
        case lastMatchWins
        /// Letters read as matching without regard to case: Docker compares names exactly.
        case letterCase
        /// An exception the builder never sees, because it skips the excluded directory above the path.
        case skippedDirectory
        /// Read with .gitignore's rules, which differ from Docker's here.
        case gitignoreRules
        /// Listing the Dockerfile or .dockerignore read as breaking the build: Docker still reads both, and only
        /// leaves them out of what `COPY` and `ADD` can see.
        case buildFilesStillRead
    }

    public enum Severity: Int, Sendable, Hashable, Comparable {
        case holds
        case unchecked
        case caution
        case wrong

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let claim: DockerignoreClaim
    public let outcome: Outcome
    /// Docker's decision on the claim's path (for a path claim).
    public let verdict: ContextVerdict?
    /// A path that shows the difference (for scope and line claims).
    public let example: String?
    /// A line that does what the claim expected, where there is an obvious one.
    public let fix: String?
    /// Flagged in an earlier review of the same conversation (set by `DockerignoreLedger`).
    public internal(set) var isRepeated = false

    init(claim: DockerignoreClaim, outcome: Outcome, verdict: ContextVerdict? = nil, example: String? = nil,
         fix: String? = nil) {
        self.claim = claim
        self.outcome = outcome
        self.verdict = verdict
        self.example = example
        self.fix = fix
    }

    public var severity: Severity {
        switch outcome {
        case .exact: .holds
        case .unchecked: .unchecked
        case .caveat: .caution
        case .wrong: .wrong
        }
    }

    /// Identifies the same claim across rewrites.
    var key: String {
        claim.key
    }
}
