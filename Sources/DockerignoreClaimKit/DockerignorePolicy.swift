/// How claims are held.
public struct DockerignorePolicy: Sendable, Hashable {
    /// Whether .dockerignore lines count as claims of their own.
    public var checksLines: Bool
    /// The builder that reads the context; `nil` when unknown, and a claim that holds only under one builder is
    /// then a caveat.
    public var builder: DockerBuilder?
    /// Whether caveats are reported (otherwise such claims hold).
    public var reportsCaveats: Bool

    public init(checksLines: Bool = true, builder: DockerBuilder? = nil, reportsCaveats: Bool = true) {
        self.checksLines = checksLines
        self.builder = builder
        self.reportsCaveats = reportsCaveats
    }

    /// Lines checked, builder unknown, caveats reported.
    public static let standard = DockerignorePolicy()

    /// Only what an answer says in prose; caveats let through.
    public static let lenient = DockerignorePolicy(checksLines: false, reportsCaveats: false)

    /// Builds run by the classic builder.
    public static let classic = DockerignorePolicy(builder: .classic)

    /// Builds run by BuildKit (`docker buildx build`, Docker Desktop).
    public static let buildKit = DockerignorePolicy(builder: .buildKit)
}
