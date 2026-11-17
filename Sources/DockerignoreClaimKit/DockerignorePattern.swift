import Foundation

/// One pattern line of a .dockerignore, as the Docker CLI reads it (`ignorefile.ReadAll`, then
/// `patternmatcher.New`).
public struct DockerignorePattern: Sendable, Hashable {
    /// The line as written.
    public let line: String
    public let lineNumber: Int
    /// A `!` line: an exception that takes a path back into the build context.
    public let isException: Bool
    /// What Docker matches paths against: white space trimmed, `filepath.Clean` applied, a leading `/` removed,
    /// without the `!`.
    public let body: String
    let program: PatternProgram?
    let problem: PatternProblem?

    /// `nil` for a comment (a line starting with `#`, even `#` after spaces is not one) or a blank line.
    init?(line: String, lineNumber: Int, reading: Reading = []) {
        var text = line
        if reading.contains(.trailingComments), let cut = Self.trailingComment(in: text) {
            text = String(text[..<cut])
        }
        guard !text.hasPrefix("#") else { return nil }
        var pattern = String(GoPath.trimSpace(Substring(text)))
        guard !pattern.isEmpty else { return nil }
        let isException = pattern.hasPrefix("!")
        if isException { pattern = String(GoPath.trimSpace(pattern.dropFirst())) }
        if !pattern.isEmpty {
            pattern = GoPath.clean(pattern)
            if pattern.count > 1, pattern.hasPrefix("/") { pattern.removeFirst() }
        }
        if reading.contains(.bangNegates) { pattern = pattern.replacingOccurrences(of: "[!", with: "[^") }
        if reading.contains(.slashlessAnyDepth), !pattern.contains("/"), !pattern.hasPrefix("**") {
            pattern = "**/" + pattern
        }
        self.line = line
        self.lineNumber = lineNumber
        self.isException = isException
        body = pattern
        let scalars = Array(pattern.unicodeScalars)
        if pattern.isEmpty || isException && pattern == "/" || !PatternSyntax.isValid(scalars) {
            program = nil
            problem = .malformed
        } else {
            do {
                program = try PatternProgram(pattern)
                problem = nil
            } catch {
                program = nil
                problem = error
            }
        }
    }

    /// Where ` # comment` starts after a pattern: white space and then `#`, not at the start of the line.
    static func trailingComment(in line: String) -> String.Index? {
        var previous: Character?
        for index in line.indices {
            if line[index] == "#", let previous, previous.isWhitespace,
               !GoPath.trimSpace(line[..<index]).isEmpty {
                return index
            }
            previous = line[index]
        }
        return nil
    }

    /// The line without its trailing comment and the spaces before it.
    static func withoutTrailingComment(_ line: String) -> String {
        guard let cut = trailingComment(in: line) else { return line }
        return String(GoPath.trimSpace(line[..<cut]))
    }

    func matches(_ path: [Unicode.Scalar], reading: Reading) -> Bool {
        guard let program else { return false }
        let crosses = reading.contains(.starCrossesSlash)
        if reading.contains(.ignoreCase) {
            return Self.folded(program).matches(path.map(Self.lower), crossesSlash: crosses)
        }
        return program.matches(path, crossesSlash: crosses)
    }

    static func lower(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        ("A"..."Z").contains(scalar) ? Unicode.Scalar(UInt8(scalar.value + 32)) : scalar
    }

    /// The program with every letter lowercased.
    static func folded(_ program: PatternProgram) -> PatternProgram {
        let body = String(String.UnicodeScalarView(program.body.map(lower)))
        return (try? PatternProgram(body)) ?? program
    }

}
