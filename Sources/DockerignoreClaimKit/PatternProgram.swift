/// One cleaned .dockerignore pattern, compiled the way `moby/patternmatcher` compiles it: an exact, prefix or
/// suffix comparison when it can, a regular expression otherwise.
struct PatternProgram: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case exact
        /// `foo/**`: anything that starts with `foo/`.
        case prefix
        /// `**/foo`, `**foo`: anything that ends with the rest.
        case suffix
        case expression
    }

    enum Token: Sendable, Hashable {
        case literal(Unicode.Scalar)
        /// `*`, which becomes `[^/]*`.
        case segment
        /// `?`, which becomes `[^/]`.
        case single
        /// `**` (and `**/`) before more pattern, which becomes `(.*/)?`.
        case directories
        /// `**` at the end, which becomes `.*`.
        case rest
        case set(negated: Bool, ranges: [ClosedRange<UInt32>])
        /// `^` outside a bracket stays a regular-expression anchor: the start of the path.
        case start
    }

    let kind: Kind
    let body: [Unicode.Scalar]
    let tokens: [Token]

    init(_ body: String) throws(PatternProblem) {
        var compiler = Compiler(scalars: Array(body.unicodeScalars))
        try compiler.run()
        kind = compiler.kind
        self.body = compiler.scalars
        tokens = compiler.tokens
    }

    /// A bracket whose members are plain characters and ranges; anything else would read differently once
    /// `patternmatcher` has rewritten `*`, `?` and `\` inside it.
    static func bracket(_ scalars: [Unicode.Scalar], from start: Int) throws(PatternProblem) -> (Token, Int) {
        var index = start
        let negated = scalars[index] == "^"
        if negated { index += 1 }
        var ranges: [ClosedRange<UInt32>] = []
        let special: Set<Unicode.Scalar> = ["\\", "*", "?", "["]
        while scalars[index] != "]" || ranges.isEmpty {
            let low = scalars[index]
            var high = low
            index += 1
            if scalars[index] == "-" {
                high = scalars[index + 1]
                index += 2
            }
            guard !special.contains(low), !special.contains(high), low.value <= high.value else { throw .unmodelled }
            ranges.append(low.value...high.value)
        }
        return (.set(negated: negated, ranges: ranges), index + 1)
    }

    /// Whether the program matches the whole path. `crossesSlash` reads `*` and `?` as also matching `/` (a
    /// misreading, for naming a wrong claim's slip).
    func matches(_ path: [Unicode.Scalar], crossesSlash: Bool = false) -> Bool {
        switch kind {
        case .exact:
            return path == body
        case .prefix:
            return path.starts(with: body.dropLast(2))
        case .suffix:
            let suffix = body.dropFirst(2)
            return path.reversed().starts(with: suffix.reversed())
                || suffix.first == "/" && ArraySlice(path) == suffix.dropFirst()
        case .expression:
            var memo: [Int: Bool] = [:]
            let walk = Walk(path: path, separator: crossesSlash ? "\u{0}" : "/")
            return run(0, 0, walk, &memo)
        }
    }

    /// Whether `tokens[token...]` matches `path[position...]` to its end.
    func run(_ token: Int, _ position: Int, _ walk: Walk, _ memo: inout [Int: Bool]) -> Bool {
        let path = walk.path
        let key = token * (path.count + 1) + position
        if let known = memo[key] { return known }
        let result = step(token, position, walk, &memo)
        memo[key] = result
        return result
    }

    func step(_ token: Int, _ position: Int, _ walk: Walk, _ memo: inout [Int: Bool]) -> Bool {
        let path = walk.path
        guard token < tokens.count else { return position == path.count }
        let here: Unicode.Scalar? = position < path.count ? path[position] : nil
        switch tokens[token] {
        case .literal(let character):
            return here == character && run(token + 1, position + 1, walk, &memo)
        case .single:
            return here.map { $0 != walk.separator } == true && run(token + 1, position + 1, walk, &memo)
        case .set(let negated, let ranges):
            guard let here else { return false }
            return ranges.contains { $0.contains(here.value) } != negated && run(token + 1, position + 1, walk, &memo)
        case .start:
            return position == 0 && run(token + 1, position, walk, &memo)
        case .segment:
            let stop = path[position...].firstIndex(of: walk.separator) ?? path.count
            return (position...stop).contains { run(token + 1, $0, walk, &memo) }
        case .rest:
            let stop = path[position...].firstIndex(of: "\n") ?? path.count
            return (position...stop).contains { run(token + 1, $0, walk, &memo) }
        case .directories:
            if run(token + 1, position, walk, &memo) { return true }
            let stop = path[position...].firstIndex(of: "\n") ?? path.count
            return (position..<stop).contains { path[$0] == "/" && run(token + 1, $0 + 1, walk, &memo) }
        }
    }
}

/// A path being matched, and the character `*` and `?` stop at.
struct Walk {
    let path: [Unicode.Scalar]
    let separator: Unicode.Scalar
}

/// The loop of `patternmatcher`'s `compile`, one character (or `**`, or bracket) at a time. Characters it escapes
/// before compiling (`.+()|{}$`) and every other plain character match themselves.
struct Compiler {
    let scalars: [Unicode.Scalar]
    var index = 0
    /// How many steps the loop has taken: `**` at the very start makes a suffix match.
    var position = 0
    var kind = PatternProgram.Kind.exact
    var tokens: [PatternProgram.Token] = []

    mutating func run() throws(PatternProblem) {
        while index < scalars.count {
            let character = scalars[index]
            index += 1
            try read(character)
            position += 1
        }
    }

    mutating func read(_ character: Unicode.Scalar) throws(PatternProblem) {
        switch character {
        case "*":
            star()
        case "?":
            add(.single)
        case "\\":
            try escape()
        case "[":
            let (set, next) = try PatternProgram.bracket(scalars, from: index)
            index = next
            add(set)
        case "]":
            add(.literal(character))
        case "^":
            tokens.append(.start)
        default:
            tokens.append(.literal(character))
        }
    }

    /// A token that makes the pattern a regular expression.
    mutating func add(_ token: PatternProgram.Token) {
        tokens.append(token)
        kind = .expression
    }

    mutating func star() {
        guard index < scalars.count, scalars[index] == "*" else { return add(.segment) }
        index += 1
        if index < scalars.count, scalars[index] == "/" { index += 1 }
        if index < scalars.count {
            add(.directories)
        } else if kind == .exact {
            kind = .prefix
        } else {
            add(.rest)
        }
        if position == 0 { kind = .suffix }
    }

    /// `\` before a character: punctuation matches itself; Go reads `\d`, `\w` and the like as classes.
    mutating func escape() throws(PatternProblem) {
        let next = scalars[index]
        index += 1
        guard next.isASCII, !next.properties.isAlphabetic, !("0"..."9").contains(next) else { throw .unmodelled }
        add(.literal(next))
    }
}
