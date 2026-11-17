/// Reads what an answer says about .dockerignore rules and checks every claim with Docker's own matching rules: the
/// one call most callers need.
public struct DockerignoreClaimChecker: Sendable {
    public let policy: DockerignorePolicy
    public let reader: DockerignoreClaimReader

    public init(policy: DockerignorePolicy = .standard) {
        self.policy = policy
        reader = DockerignoreClaimReader(checksLines: policy.checksLines)
    }

    public func claims(in text: String, context: String = "") -> [DockerignoreClaim] {
        reader.claims(in: text, context: context)
    }

    public func judge(_ claim: DockerignoreClaim) -> DockerignoreFinding {
        DockerignoreEvaluator(policy: policy).judge(claim)
    }

    /// Every claim's finding. A .dockerignore line that works as written makes no finding of its own, so that an
    /// answer with a long .dockerignore is not reported as a long list of claims that hold. `context` is other text
    /// from the conversation (the question, say).
    public func check(_ text: String, context: String = "") -> DockerignoreReport {
        report(claims(in: text, context: context))
    }

    func report(_ claims: [DockerignoreClaim]) -> DockerignoreReport {
        DockerignoreReport(findings: claims.map(judge).filter { $0.claim.isExplicit || $0.severity != .holds })
    }
}

/// Checks a conversation's answers one after another and remembers what it flagged, so a wrong claim stated again
/// after a correction was asked for is marked as repeated rather than new.
public actor DockerignoreLedger {
    public struct Statistics: Sendable, Hashable {
        public var reviews = 0
        public var claims = 0
        public var flagged = 0
        public var repeated = 0
    }

    public nonisolated let checker: DockerignoreClaimChecker
    public private(set) var statistics = Statistics()
    private var flaggedKeys: Set<String> = []
    /// Whether the last answer reviewed, or its context, named .dockerignore.
    public private(set) var isAboutDockerignore = false

    public init(checker: DockerignoreClaimChecker = DockerignoreClaimChecker()) {
        self.checker = checker
    }

    /// Checks one answer. `context` is the question it answers. A turn where neither names .dockerignore makes no
    /// new claims from its sentences' own patterns; it keeps only those that repeat a claim flagged earlier in the
    /// conversation, so "you're right, `node_modules` does match `app/node_modules`" after a correction is caught.
    public func review(_ text: String, context: String = "") -> DockerignoreReport {
        isAboutDockerignore = DockerignoreClaimReader.isAboutDockerignore(context)
            || DockerignoreClaimReader.isAboutDockerignore(text)
        let all = checker.reader.claims(in: text, assumingDockerContext: true)
        let claims = isAboutDockerignore ? all : all.filter { !$0.restsOnSentence || flaggedKeys.contains($0.key) }
        var findings = checker.report(claims).findings
        var keys: Set<String> = []
        for index in findings.indices where findings[index].severity >= .caution {
            let key = findings[index].key
            findings[index].isRepeated = flaggedKeys.contains(key)
            keys.insert(key)
        }
        flaggedKeys.formUnion(keys)
        let report = DockerignoreReport(findings: findings)
        statistics.reviews += 1
        statistics.claims += findings.count
        statistics.flagged += report.flagged.count
        statistics.repeated += report.repeatedCount
        return report
    }

    /// Starts a new conversation: nothing flagged so far counts as a repeat.
    public func forget() {
        flaggedKeys.removeAll()
        isAboutDockerignore = false
    }
}
