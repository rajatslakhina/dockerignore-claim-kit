/// Finds everything an answer says about .dockerignore rules: in its prose, and in the .dockerignore files it shows.
public struct DockerignoreClaimReader: Sendable {
    /// Whether the lines of a .dockerignore count as claims of their own (a ` # comment` after a pattern; a `!`
    /// line naming a path).
    public let checksLines: Bool

    public init(checksLines: Bool = true) {
        self.checksLines = checksLines
    }

    /// Whether the text talks about .dockerignore. Without that (in the answer, or in the context a caller passes)
    /// a sentence such as "`*.log` matches `logs/a.log`" is about something else, often .gitignore, where it holds.
    public static func isAboutDockerignore(_ text: String) -> Bool {
        text.folded.contains("dockerignore")
    }

    /// The claims in an answer. `context` is other text from the conversation (the question it answers); when it,
    /// or the answer, names .dockerignore, a sentence's own patterns are read as .dockerignore rules.
    public func claims(in text: String, context: String = "") -> [DockerignoreClaim] {
        claims(in: text, context: context, assumingDockerContext: Self.isAboutDockerignore(context))
    }

    func claims(in text: String, context: String, assumingDockerContext: Bool) -> [DockerignoreClaim] {
        let found = allClaims(in: text, context: context)
        guard !assumingDockerContext, !Self.isAboutDockerignore(text) else { return found }
        return found.filter { !$0.restsOnSentence }
    }

    /// `context` counts when deciding whether the conversation also talks about another ignore file: an answer to
    /// "does `*.log` cover nested logs in my .gitignore?" is about .gitignore even if it never says so.
    func allClaims(in text: String, context: String = "") -> [DockerignoreClaim] {
        let blocks = AnswerBlocks.split(text)
        let ruleBlocks = RuleBlocks.find(in: blocks)
        let mentionsOtherFiles = RuleBlocks.otherFiles.contains { (text + "\n" + context).folded.contains($0) }
        var claims: [DockerignoreClaim] = []
        if checksLines { claims += ruleBlocks.flatMap(LineReader.claims) }
        for (position, block) in blocks.enumerated() where block.kind == .prose {
            let reading = self.context(at: position, ruleBlocks)
            for sentence in Sentences.split(block.lines) where Self.isOurs(sentence, mentionsOtherFiles) {
                claims += StatementReader.claims(in: sentence)
                claims += SentenceReader(context: reading).claims(in: sentence)
            }
        }
        return Self.deduplicated(claims)
    }

    /// In an answer (or a question) that also talks about .gitignore or another ignore file, only sentences that
    /// name Docker are read: "`*.log` matches `logs/a.log`" holds for .gitignore and not for .dockerignore.
    static func isOurs(_ sentence: String, _ mentionsOtherFiles: Bool) -> Bool {
        let folded = sentence.folded
        if folded.contains("dockerignore") { return true }
        if RuleBlocks.otherFiles.contains(where: folded.contains) { return false }
        return !mentionsOtherFiles || ["docker", "build context", "image"].contains { Words.contains(folded, $0) }
    }

    /// The .dockerignore a sentence is about: the nearest one before it, else the first one after it.
    func context(at position: Int, _ ruleBlocks: [RuleBlock]) -> ReadingContext {
        guard let block = ruleBlocks.last(where: { $0.position < position }) ?? ruleBlocks.first else {
            return ReadingContext(rules: nil, source: .none, blockLines: [])
        }
        let lines = Set(block.lines.map(\.trimmed).filter { !$0.isEmpty })
        return ReadingContext(rules: DockerignoreRules(block.text), source: .block(block.number), blockLines: lines)
    }

    /// One claim per subject and assertion: a sentence restating what a line already implies replaces it.
    static func deduplicated(_ claims: [DockerignoreClaim]) -> [DockerignoreClaim] {
        func key(_ claim: DockerignoreClaim) -> String { "\(claim.kind)|\(claim.subject)|\(claim.assertion)" }
        let stated = Set(claims.filter(\.isExplicit).map(key))
        var seen: Set<String> = []
        return claims.filter { claim in
            (claim.isExplicit || !stated.contains(key(claim))) && seen.insert(key(claim)).inserted
        }
    }
}
