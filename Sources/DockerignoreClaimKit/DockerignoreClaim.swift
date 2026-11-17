/// One thing an answer says about .dockerignore rules.
public struct DockerignoreClaim: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// A path is, or is not, left out of the build context.
        case path
        /// A pattern matches at any depth, or only at the root of the context.
        case scope
        /// A .dockerignore line does what it was written to do (a pattern with a ` # comment` after it).
        case line
        /// A .dockerignore in a subdirectory applies (or does not) to that directory.
        case location
        /// Listing the Dockerfile or .dockerignore itself breaks (or does not break) the build.
        case buildFiles
    }

    public enum Assertion: String, Sendable, Hashable, CaseIterable {
        case excluded
        case included
        case anyDepth
        case rootOnly
        case takesEffect
        case nestedFileApplies
        case nestedFileIgnored
        case buildFails
        case buildWorks
    }

    /// Where the rules a claim is judged against come from.
    public enum Source: Sendable, Hashable {
        /// The answer's n-th .dockerignore (1-based).
        case block(Int)
        /// Patterns named in the sentence itself.
        case sentence([String])
        /// Nothing to judge against: a statement about how Docker reads the file needs no rules.
        case none
    }

    public let kind: Kind
    /// The path, pattern or line the claim is about.
    public let subject: String
    public let assertion: Assertion
    /// The sentence (or .dockerignore line) it was read from.
    public let sentence: String
    /// Stated in prose, rather than implied by a line of a .dockerignore.
    public let isExplicit: Bool
    public let source: Source
    let rules: DockerignoreRules?

    /// Identifies the same claim across rewrites.
    var key: String {
        "\(kind)|\(subject)|\(assertion)".lowercased()
    }

    /// Whether it rests only on the patterns its sentence names.
    var restsOnSentence: Bool {
        if case .sentence = source { true } else { false }
    }

    init(kind: Kind, subject: String, assertion: Assertion, sentence: String, isExplicit: Bool = true,
         source: Source = .none, rules: DockerignoreRules? = nil) {
        self.kind = kind
        self.subject = subject
        self.assertion = assertion
        self.sentence = sentence
        self.isExplicit = isExplicit
        self.source = source
        self.rules = rules
    }
}
