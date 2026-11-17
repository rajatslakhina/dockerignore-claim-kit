import Foundation

/// A .dockerignore an answer shows in a fenced code block.
struct RuleBlock: Equatable {
    let lines: [String]
    /// Position among the answer's blocks of all kinds, prose included.
    let position: Int
    /// 1-based among the answer's .dockerignore files.
    let number: Int
    /// Introduced as what not to do ("this does not work:"), so its lines are not held to their intent.
    let isCounterexample: Bool

    var text: String { lines.joined(separator: "\n") + "\n" }
}

enum RuleBlocks {
    static let plainTags: Set = ["", "text", "txt", "plaintext", "plain", "conf", "ini", "ignore", "bash", "sh",
                                 "shell"]
    /// Ignore files Docker does not read.
    static let otherFiles = [".gitignore", ".npmignore", ".eslintignore", ".prettierignore", ".helmignore",
                             ".gcloudignore", ".vscodeignore", ".slugignore", ".cfignore", ".stylelintignore",
                             ".containerignore"]
    static let counterexampleMarkers = ["doesn't work", "does not work", "won't work", "will not work", "wrong",
                                        "incorrect", "broken", "instead of", "not this", "avoid", "don't do",
                                        "do not do", "bad:", "before:", "mistake", "common error"]

    /// Every .dockerignore at the root of the build context that the answer shows, in order. A
    /// `app/.dockerignore` is left out: Docker reads only the one at the root of the context.
    static func find(in blocks: [AnswerBlock]) -> [RuleBlock] {
        var found: [RuleBlock] = []
        for (position, block) in blocks.enumerated() {
            guard case .code(let tag) = block.kind else { continue }
            let lead = position > 0 && blocks[position - 1].kind == .prose
                ? blocks[position - 1].lines.suffix(3).joined(separator: " ").folded : ""
            guard isDockerignore(tag: tag, lines: block.lines, lead: lead) else { continue }
            let counter = Words.containsAny(String(lead.suffix(160)), counterexampleMarkers)
            found.append(RuleBlock(lines: block.lines, position: position, number: found.count + 1,
                                   isCounterexample: counter))
        }
        return found
    }

    static func isDockerignore(tag: String, lines: [String], lead: String) -> Bool {
        let header = lines.first?.trimmed.folded ?? ""
        let named = header.hasPrefix("#") ? header : ""
        if named.contains(".dockerignore") { return !isNested(named) }
        if otherFiles.contains(where: named.contains) { return false }
        if tag == "dockerignore" || tag == ".dockerignore" { return !isNested(lead) }
        guard plainTags.contains(tag), looksLikePatterns(lines), let last = lastFileName(in: lead) else { return false }
        return last == ".dockerignore" && !isNested(lead)
    }

    /// The ignore file the text names last.
    static func lastFileName(in text: String) -> String? {
        ([".dockerignore"] + otherFiles).compactMap { name in
            text.range(of: name, options: .backwards).map { (name, $0.lowerBound) }
        }.max { $0.1 < $1.1 }?.0
    }

    /// Whether the text names a .dockerignore inside a directory (`app/.dockerignore`), which Docker does not read.
    static func isNested(_ text: String) -> Bool {
        guard let range = text.range(of: "/.dockerignore", options: .backwards) else { return false }
        let before = text[..<range.lowerBound]
        let start = before.lastIndex { " `'\"(:".contains($0) }.map { before.index(after: $0) } ?? before.startIndex
        let directory = before[start...]
        return !directory.isEmpty && directory != "." && directory != "~"
    }

    /// Whether every line could be a .dockerignore line rather than a command or code.
    static func looksLikePatterns(_ lines: [String]) -> Bool {
        let content = lines.map(\.trimmed).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let commands = ["$", ">", "git ", "docker ", "echo ", "cat ", "cd ", "touch ", "mkdir ", "npm ", "rm ",
                        "printf ", "FROM ", "COPY ", "RUN "]
        return !content.isEmpty && !content.contains { line in
            commands.contains { line.hasPrefix($0) } || line.contains("=") || line.hasSuffix(";") || line.hasSuffix("{")
        }
    }
}
