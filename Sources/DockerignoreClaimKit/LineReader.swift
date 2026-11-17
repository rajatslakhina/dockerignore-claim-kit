import Foundation

/// Claims a .dockerignore makes by its lines alone: a pattern with a ` # comment` after it is meant to work, and a
/// `!` line naming a path is meant to bring that path back into the build context.
enum LineReader {
    static func claims(in block: RuleBlock) -> [DockerignoreClaim] {
        guard !block.isCounterexample else { return [] }
        let rules = DockerignoreRules(block.text)
        var claims: [DockerignoreClaim] = []
        for raw in block.lines {
            let line = raw.trimmingCharacters(in: .newlines)
            guard !line.hasPrefix("#"), !line.trimmed.isEmpty else { continue }
            if DockerignorePattern.trailingComment(in: line) != nil {
                claims.append(DockerignoreClaim(kind: .line, subject: line, assertion: .takesEffect, sentence: line,
                                                isExplicit: false, source: .block(block.number), rules: rules))
                continue
            }
            guard line.trimmed.hasPrefix("!"), let literal = SentenceReader.literal(line.trimmed) else { continue }
            claims.append(DockerignoreClaim(kind: .path, subject: DockerignoreRules.normalize(literal),
                                            assertion: .included, sentence: line, isExplicit: false,
                                            source: .block(block.number), rules: rules))
        }
        return claims
    }
}
