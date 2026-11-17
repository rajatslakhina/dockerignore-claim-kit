import Foundation

/// Sentences about how Docker reads the file itself, not about one path: "add a `.dockerignore` to each service
/// folder", "excluding the Dockerfile breaks the build".
enum StatementReader {
    static let nestedPhrases = ["in each subdirectory", "in every subdirectory", "in each folder", "in every folder",
                                "in subdirectories", "in subfolders", "in each subfolder", "in every subfolder",
                                "in each directory", "in every directory", "nested .dockerignore",
                                "per-directory .dockerignore", "per-folder .dockerignore", "in each service"]
    /// Words before the mention that deny it ("Docker ignores", "not", "only reads the root one").
    static let denials: Set = ["not", "never", "only", "ignores", "unlike", "instead", "cannot", "nor"]
    /// Words just after it that deny it ("is ignored", "has no effect", "isn't read").
    static let laterDenials: Set = ["not", "never", "ignored", "no", "nothing", "cannot"]
    static let failures = ["break", "breaks", "broke", "fail", "fails", "failed", "won't build", "will not build",
                           "can't find", "cannot find", "won't find", "will not find", "not found", "error",
                           "errors", "missing"]
    static let reassurances = ["still", "doesn't break", "does not break", "won't break", "will not break",
                               "no problem", "no error", "is fine", "safe to"]

    static func claims(in sentence: String) -> [DockerignoreClaim] {
        guard !sentence.hasSuffix("?") else { return [] }
        return location(sentence) + buildFiles(sentence)
    }

    /// "Put a `.dockerignore` in each service folder": Docker reads only the one at the root of the build context.
    static func location(_ sentence: String) -> [DockerignoreClaim] {
        let folded = sentence.folded
        let spans = Sentences.pieces(sentence).filter(\.isCode).map(\.text)
        let mention = spans.first { RuleBlocks.isNested($0.folded) }.map { ($0, $0.folded) }
            ?? nestedPhrases.first { folded.contains($0) }.map { (".dockerignore", $0) }
        guard let (subject, text) = mention, folded.contains("dockerignore"),
              let range = folded.range(of: text),
              !Clauses.words(folded).contains(where: Clauses.conditions.contains) else { return [] }
        let before = Clauses.words(String(folded[..<range.lowerBound]))
        let after = Clauses.words(String(folded[range.upperBound...])).prefix(3)
        let denied = before.contains { denials.contains($0) || $0.hasSuffix("n't") }
            || after.contains { laterDenials.contains($0) || $0.hasSuffix("n't") }
        return [DockerignoreClaim(kind: .location, subject: subject,
                                  assertion: denied ? .nestedFileIgnored : .nestedFileApplies, sentence: sentence)]
    }

    /// "Don't list the Dockerfile, or the build fails": Docker still reads the Dockerfile and .dockerignore.
    static func buildFiles(_ sentence: String) -> [DockerignoreClaim] {
        let folded = sentence.folded.replacingOccurrences(of: "`", with: "")
        let named = ["dockerfile", ".dockerignore itself"].first { Words.contains(folded, $0) }
        let listing = ["exclude", "excluding", "excluded", "ignore", "ignoring", "ignored", "list", "listing",
                       "listed", "add", "adding", "put"].contains { Words.contains(folded, $0) }
        guard let named, listing, failures.contains(where: { Words.contains(folded, $0) }) else { return [] }
        let reassured = reassurances.contains { Words.contains(folded, $0) }
        return [DockerignoreClaim(kind: .buildFiles, subject: named == "dockerfile" ? "Dockerfile" : ".dockerignore",
                                  assertion: reassured ? .buildWorks : .buildFails, sentence: sentence)]
    }
}
