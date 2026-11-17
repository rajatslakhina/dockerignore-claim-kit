/// Which builder walks the build context. They read patterns the same way; they differ in when a directory that a
/// pattern excludes is still searched for exceptions.
public enum DockerBuilder: String, Sendable, Hashable, CaseIterable {
    /// The classic builder (`docker build` without buildx). An excluded directory is searched only when an
    /// exception's text starts with the directory's path, so `!**/keep.txt` cannot bring back
    /// `node_modules/pkg/keep.txt`. Checked against Docker 27.5 on this package's parity fixture.
    case classic
    /// BuildKit (`docker buildx build`, Docker Desktop's default). As `tonistiigi/fsutil` reads: when any exception
    /// holds a wildcard, every excluded directory is searched. Taken from that source, not run here.
    case buildKit
}

/// The rules of one .dockerignore, at the root of a build context.
public struct DockerignoreRules: Sendable, Hashable {
    /// The file as written.
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    /// The pattern lines, in file order.
    public var patterns: [DockerignorePattern] {
        patterns(reading: [])
    }

    func patterns(reading: Reading) -> [DockerignorePattern] {
        let lines = GoPath.lines(text)
        return lines.enumerated().compactMap { offset, line in
            let text = offset == 0 && line.hasPrefix("\u{FEFF}") ? String(line.dropFirst()) : line
            return DockerignorePattern(line: text, lineNumber: offset + 1, reading: reading)
        }
    }

    /// A line Docker rejects (so `docker build` stops), or one this package does not model, if there is one.
    public var problem: (line: DockerignorePattern, problem: PatternProblem)? {
        let found = patterns.compactMap { pattern in pattern.problem.map { (pattern, $0) } }
        return found.first { $0.1 == .malformed } ?? found.first
    }

    /// Whether `path` (relative to the build context; a leading `./` or `/` and a trailing `/` are dropped) is left
    /// out of the build context, and why.
    public func verdict(for path: String, builder: DockerBuilder = .classic) -> ContextVerdict {
        verdict(Self.normalize(path), builder: builder, reading: [])
    }

    func verdict(_ path: String, builder: DockerBuilder, reading: Reading) -> ContextVerdict {
        let all = patterns(reading: reading)
        let components = path.split(separator: "/").map(String.init)
        for depth in 1..<max(components.count, 1) {
            let directory = components.prefix(depth).joined(separator: "/")
            let decided = Self.decide(all, directory, reading)
            guard decided.isExcluded else { continue }
            if reading.contains(.excludedParentIsFinal) || Self.skips(directory, all, builder) {
                return ContextVerdict(isExcluded: true, decidingPattern: decided.pattern,
                                      skippedDirectory: directory + "/")
            }
        }
        let decided = Self.decide(all, path, reading)
        return ContextVerdict(isExcluded: decided.isExcluded, decidingPattern: decided.pattern, skippedDirectory: nil)
    }

    /// `MatchesOrParentMatches`: lines in order, each able to flip the result; an exclusion line is tried only while
    /// the path is in, an exception only while it is out. A line also matches when it matches a parent directory.
    static func decide(_ patterns: [DockerignorePattern], _ path: String,
                       _ reading: Reading) -> (isExcluded: Bool, pattern: DockerignorePattern?) {
        let scalars = Array(path.unicodeScalars)
        let names = path.split(separator: "/")
        let parents = names.dropLast().indices.map { Array(names.prefix($0 + 1).joined(separator: "/").unicodeScalars) }
        let hits: (DockerignorePattern) -> Bool = { pattern in
            pattern.matches(scalars, reading: reading) || parents.contains { pattern.matches($0, reading: reading) }
        }
        if reading.contains(.firstMatchWins) {
            let first = patterns.first(where: hits)
            return (first.map { !$0.isException } ?? false, first)
        }
        var excluded = false
        var decider: DockerignorePattern?
        for pattern in patterns where pattern.isException == excluded && hits(pattern) {
            excluded = !pattern.isException
            decider = pattern
        }
        return (excluded, decider)
    }

    /// Whether the builder skips an excluded directory instead of searching it for exceptions.
    static func skips(_ directory: String, _ patterns: [DockerignorePattern], _ builder: DockerBuilder) -> Bool {
        let exceptions = patterns.filter(\.isException)
        var bodies = exceptions.map(\.body)
        if builder == .buildKit {
            bodies = bodies.map(Self.withoutTrailingGlob)
            if bodies.contains(where: { $0.contains(where: "*[]?^\\".contains) }) { return false }
        }
        return !bodies.contains { ($0 + "/").hasPrefix(directory + "/") }
    }

    /// fsutil's `patternWithoutTrailingGlob`: `src/**` and `src/*` read as `src`.
    static func withoutTrailingGlob(_ body: String) -> String {
        var body = body
        if body.hasSuffix("/**") { body.removeLast(3) }
        if body.hasSuffix("/*") { body.removeLast(2) }
        return body
    }

    /// Strips `./` and a leading `/`, and a trailing `/`.
    static func normalize(_ path: String) -> String {
        var text = path
        while text.hasPrefix("./") { text.removeFirst(2) }
        while text.hasPrefix("/") { text.removeFirst() }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

/// What Docker decides about one path.
public struct ContextVerdict: Sendable, Hashable {
    /// Left out of the build context, so `COPY` and `ADD` cannot see it (and a `COPY . .` leaves it out of the
    /// image; files a `RUN` step makes are another matter).
    public let isExcluded: Bool
    /// The line that decided it: the last line that changed the result, or the line that excluded a skipped
    /// directory.
    public let decidingPattern: DockerignorePattern?
    /// The excluded directory (ending in `/`) the builder did not search, when that is what decided it.
    public let skippedDirectory: String?
}
