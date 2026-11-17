/// Why Docker cannot use, or this package does not model, a .dockerignore line.
public enum PatternProblem: Error, Sendable, Hashable {
    /// `filepath.Match` rejects it (an unclosed `[`, a trailing `\`, `!` alone): `docker build` stops with an error.
    case malformed
    /// Docker accepts it, but turns it into a regular expression this package does not reproduce (a bracket holding
    /// `*`, `?`, `[` or `\`, a reversed range, `\` before a letter or digit).
    case unmodelled
}

/// The syntax check Docker makes with `filepath.Match(pattern, ".")`: every bracket and escape must be well formed.
enum PatternSyntax {
    static func isValid(_ scalars: [Unicode.Scalar]) -> Bool {
        var index = 0
        while index < scalars.count {
            switch scalars[index] {
            case "\\":
                guard index + 1 < scalars.count else { return false }
                index += 2
            case "[":
                guard let next = bracketEnd(scalars, after: index) else { return false }
                index = next
            default:
                index += 1
            }
        }
        return true
    }

    /// The index after a well-formed bracket that opens at `open`, or `nil`.
    static func bracketEnd(_ scalars: [Unicode.Scalar], after open: Int) -> Int? {
        var index = open + 1
        if index < scalars.count, scalars[index] == "^" { index += 1 }
        var ranges = 0
        while index >= scalars.count || scalars[index] != "]" || ranges == 0 {
            guard let low = member(scalars, at: index) else { return nil }
            index = low
            if scalars[index] == "-" {
                guard let high = member(scalars, at: index + 1) else { return nil }
                index = high
            }
            ranges += 1
        }
        return index + 1
    }

    /// `getEsc`: the index after one member of a bracket, which must be followed by something.
    static func member(_ scalars: [Unicode.Scalar], at index: Int) -> Int? {
        guard index < scalars.count, scalars[index] != "-", scalars[index] != "]" else { return nil }
        let end = scalars[index] == "\\" ? index + 2 : index + 1
        return end < scalars.count ? end : nil
    }
}
