@testable import DockerignoreClaimKit
import Testing

@Suite("Matching")
struct MatcherTests {
    @Test("filepath.Clean", arguments: [
        ("", "."), ("a//b/", "a/b"), ("./a", "a"), ("a/../b", "b"), ("../a", "../a"), ("a/../..", ".."),
        ("/../a", "/a"), ("a/..", "."), ("/", "/")
    ])
    func clean(_ input: String, _ expected: String) {
        #expect(GoPath.clean(input) == expected)
    }

    @Test("lines and white space, the way bufio.Scanner and strings.TrimSpace read them")
    func lines() {
        #expect(GoPath.lines("a\r\nb") == ["a", "b"])
        #expect(GoPath.lines("") == [])
        #expect(GoPath.lines("a\n\n") == ["a", ""])
        #expect(GoPath.trimSpace("  a \t") == "a")
        #expect(GoPath.trimSpace("   ").isEmpty)
    }

    @Test("filepath.Match's syntax check", arguments: [
        ("[a", false), ("a\\", false), ("[]", false), ("[^]", false), ("[a-]", false), ("[-a]", false),
        ("[a-", false), ("[a-c]", true), ("[\\]]", true), ("[^a-c]x", true), ("a\\*", true), ("plain", true)
    ])
    func syntax(_ pattern: String, _ valid: Bool) {
        #expect(PatternSyntax.isValid(Array(pattern.unicodeScalars)) == valid)
    }

    @Test("how patternmatcher compiles each kind")
    func kinds() throws {
        #expect(try PatternProgram("a").kind == .exact)
        #expect(try PatternProgram("a/**").kind == .prefix)
        #expect(try PatternProgram("**/a").kind == .suffix)
        #expect(try PatternProgram("**a").kind == .suffix)
        #expect(try PatternProgram("a*").kind == .expression)
        let rest = try PatternProgram("*/**")
        #expect(rest.tokens.last == .rest)
        #expect(rest.matches(Array("x/y/z".unicodeScalars)))
        #expect(!rest.matches(Array("x".unicodeScalars)))
        #expect(!rest.matches(Array("x/a\nb".unicodeScalars)))
        #expect(!(try PatternProgram("a/**/b")).matches(Array("a/x\ny/b".unicodeScalars)))
        #expect(try PatternProgram("a/**/b").matches(Array("a/x/y/b".unicodeScalars)))
    }

    @Test("patterns Docker accepts but this package does not model", arguments: ["a\\q", "[a*]", "[z-a]", "[a?]"])
    func unmodelled(_ pattern: String) {
        #expect(throws: PatternProblem.unmodelled) { try PatternProgram(pattern) }
        #expect(DockerignorePattern(line: pattern, lineNumber: 1)?.problem == .unmodelled)
    }

    @Test("a `*` that may cross `/`, for naming a slip")
    func crossing() throws {
        let program = try PatternProgram("doc/*.txt")
        #expect(!program.matches(Array("doc/a/b.txt".unicodeScalars)))
        #expect(program.matches(Array("doc/a/b.txt".unicodeScalars), crossesSlash: true))
        #expect(try PatternProgram("doc/?.txt").matches(Array("doc/a.txt".unicodeScalars)))
    }

    @Test("lines: comments, exceptions and cleaning")
    func patterns() throws {
        #expect(DockerignorePattern(line: "#a", lineNumber: 1) == nil)
        #expect(DockerignorePattern(line: "   ", lineNumber: 1) == nil)
        #expect(try #require(DockerignorePattern(line: "  #a", lineNumber: 1)).body == "#a")
        let spaced = try #require(DockerignorePattern(line: " ! ./a/ ", lineNumber: 2))
        #expect(spaced.isException && spaced.body == "a" && spaced.lineNumber == 2)
        #expect(DockerignorePattern(line: "!", lineNumber: 1)?.problem == .malformed)
        #expect(DockerignorePattern(line: "!/", lineNumber: 1)?.problem == .malformed)
        #expect(DockerignorePattern(line: "/", lineNumber: 1)?.body == "/")
        #expect(DockerignorePattern(line: "/a", lineNumber: 1)?.body == "a")
        #expect(DockerignorePattern.trailingComment(in: "a # b") != nil)
        #expect(DockerignorePattern.trailingComment(in: "# a") == nil)
        #expect(DockerignorePattern.trailingComment(in: "a#b") == nil)
        #expect(DockerignorePattern.withoutTrailingComment("a   # b") == "a")
        #expect(DockerignorePattern.withoutTrailingComment("a") == "a")
        let commented = try #require(DockerignorePattern(line: "logs # old", lineNumber: 1, reading: .trailingComments))
        #expect(commented.body == "logs")
    }

    @Test("a file's first problem: one Docker rejects before one it accepts")
    func problems() {
        #expect(DockerignoreRules("[a*]\n[a\n").problem?.problem == .malformed)
        #expect(DockerignoreRules("[a*]\n").problem?.line.lineNumber == 1)
        #expect(DockerignoreRules("a\n").problem == nil)
        #expect(DockerignoreRules("\u{FEFF}a.txt\n").patterns.first?.body == "a.txt")
    }

    @Test("paths are read relative to the context root")
    func normalize() {
        let rules = DockerignoreRules("a\n")
        #expect(rules.verdict(for: "./a/").isExcluded)
        #expect(rules.verdict(for: "/a").isExcluded)
        #expect(!rules.verdict(for: "b").isExcluded)
        #expect(rules.verdict(for: "b").decidingPattern == nil)
    }

    @Test("the two builders disagree only on when an excluded directory is searched")
    func builders() {
        let wildcard = DockerignoreRules("node_modules\n!**/keep.txt\n")
        let classic = wildcard.verdict(for: "node_modules/pkg/keep.txt", builder: .classic)
        #expect(classic.isExcluded && classic.skippedDirectory == "node_modules/")
        #expect(!wildcard.verdict(for: "node_modules/pkg/keep.txt", builder: .buildKit).isExcluded)
        let literal = DockerignoreRules("node_modules\n!node_modules/pkg/keep.txt\n")
        for builder in DockerBuilder.allCases {
            #expect(!literal.verdict(for: "node_modules/pkg/keep.txt", builder: builder).isExcluded)
        }
        let globbed = DockerignoreRules("*\n!src/**\n")
        #expect(!globbed.verdict(for: "src/a/b.go", builder: .buildKit).isExcluded)
        #expect(!DockerignoreRules("src\n!vendor/a\n").verdict(for: "vendor/a").isExcluded)
        #expect(DockerignoreRules("src\n!vendor/a\n").verdict(for: "src/x", builder: .buildKit).skippedDirectory == "src/")
        #expect(DockerignoreRules.withoutTrailingGlob("a/**") == "a")
        #expect(DockerignoreRules.withoutTrailingGlob("a/*") == "a")
        #expect(DockerignoreRules.withoutTrailingGlob("a/**/*") == "a/**")
    }

    @Test("misreadings change the verdict the way their names say")
    func readings() {
        let rules = DockerignoreRules("!README.md\n*.md\n")
        #expect(rules.verdict("README.md", builder: .classic, reading: []).isExcluded)
        #expect(!rules.verdict("README.md", builder: .classic, reading: .firstMatchWins).isExcluded)
        #expect(!DockerignoreRules("x\n").verdict("y", builder: .classic, reading: .firstMatchWins).isExcluded)
        #expect(DockerignoreRules("README.md\n").verdict("readme.md", builder: .classic, reading: .ignoreCase)
            .isExcluded)
        #expect(DockerignoreRules("logs\n!logs/a\n").verdict("logs/a", builder: .classic,
                                                             reading: .excludedParentIsFinal).isExcluded)
        #expect(DockerignoreRules("[!a].txt\n").verdict("b.txt", builder: .classic, reading: .bangNegates).isExcluded)
        #expect(DockerignoreRules("*.log\n").verdict("a/b.log", builder: .classic, reading: .slashlessAnyDepth)
            .isExcluded)
        // Lowercased, `[Z-a]` would be a reversed range, so the pattern is kept as written.
        #expect(!DockerignoreRules("[Z-a]x\n").verdict("Zx", builder: .classic, reading: .ignoreCase).isExcluded)
    }
}
