/// The parts of Go's `path/filepath` and `strings` that the Docker CLI applies to .dockerignore lines.
enum GoPath {
    /// `filepath.Clean` on a slash-separated path: repeated slashes, `.` and resolvable `..` removed, no trailing
    /// slash, `.` for an empty result.
    static func clean(_ path: String) -> String {
        guard !path.isEmpty else { return "." }
        let rooted = path.hasPrefix("/")
        var parts: [Substring] = []
        for part in path.split(separator: "/") where part != "." {
            if part != ".." {
                parts.append(part)
            } else if let last = parts.last, last != ".." {
                parts.removeLast()
            } else if !rooted {
                parts.append(part)
            }
        }
        let joined = (rooted ? "/" : "") + parts.joined(separator: "/")
        return joined.isEmpty ? "." : joined
    }

    /// `strings.TrimSpace`: leading and trailing Unicode white space.
    static func trimSpace(_ text: Substring) -> Substring {
        let isSpace: (Character) -> Bool = { $0.isWhitespace }
        guard let start = text.firstIndex(where: { !isSpace($0) }),
              let end = text.lastIndex(where: { !isSpace($0) }) else { return "" }
        return text[start...end]
    }

    /// The lines `bufio.Scanner` yields: split at `\n`, a trailing `\r` dropped, no empty last line. Split by
    /// Unicode scalar, because `\r\n` is a single `Character`.
    static func lines(_ text: String) -> [String] {
        var lines = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { slice in
            var scalars = String.UnicodeScalarView(slice)
            if scalars.last == "\r" { scalars.removeLast() }
            return String(scalars)
        }
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }
}
