/// The verbs and phrases that state whether something is left out of the build context.
enum Lexicon {
    enum Polarity: Equatable {
        case excluded
        case kept
        /// "works" / "has no effect": said of a negated line.
        case works
    }

    static let excludedVerbs: Set = ["ignores", "ignored", "ignore", "excludes", "excluded", "exclude", "matches",
                                     "matched", "match", "catches", "caught", "catch", "covers", "covered", "hides",
                                     "hidden", "omitted", "omits", "skips", "skipped", "skip", "drops", "dropped",
                                     "filters", "filtered", "strips", "stripped", "prunes", "pruned"]
    static let keptVerbs: Set = ["re-includes", "re-included", "re-include", "reincludes", "reincluded",
                                 "reinclude", "un-ignores", "un-ignored", "un-ignore", "unignores", "unignored",
                                 "unignore", "whitelists", "whitelisted", "whitelist", "allowlists", "allowlisted",
                                 "keeps", "kept", "restores", "restored", "includes", "included", "include", "sends",
                                 "sent", "send", "copies", "copied", "copy", "uploads", "uploaded"]
    static let workVerbs: Set = ["works", "work", "effect", "nothing"]
    static let participles: Set = ["hidden", "kept", "caught", "sent", "left"]
    /// Verbs said of the path itself, like a passive: "`logs/keep.log` shows up in the image".
    static let intransitive: Set = ["shows", "show", "appears", "appear", "ends", "end", "makes", "make", "made"]
    static let negations: Set = ["not", "never", "cannot", "nor", "neither"]
    static let skips: Set = ["should", "must", "need", "needs", "want", "wants", "try", "can", "could", "may",
                             "might", "to", "let", "lets", "help", "helps", "how", "please", "make", "makes"]
    static let beWords: Set = ["is", "are", "be", "been", "being", "stays", "stay", "remains", "remain", "gets",
                               "get", "still", "will", "won't", "isn't", "aren't", "was", "were", "also", "now",
                               "then", "only"]
    static let scopeAnywhere = ["at any depth", "any depth", "at any level", "at every level", "every level",
                                "any level", "anywhere", "everywhere", "in any directory", "in any folder",
                                "in every directory", "in every folder", "in all directories", "in all folders",
                                "in any subdirectory", "in any subfolder", "in every subdirectory", "recursively",
                                "throughout the repo", "throughout the repository", "throughout the project",
                                "throughout the context", "no matter how deep", "however deep", "at all levels",
                                "nested directories", "in subdirectories", "in subfolders"]
    static let scopeTop = ["root", "top level", "top-level", "context root", "root of the context",
                           "root of the build context", "top of the context"]

    /// A verb found in a clause.
    struct Verb {
        let index: Int
        let polarity: Polarity
        let word: String
    }

    /// The first verb in the tokens: its index and polarity. "brings back" and "shows up" count as one verb.
    static func verb(in tokens: [Clause.Token]) -> Verb? {
        for (index, token) in tokens.enumerated() {
            guard case .word(let word) = token else { continue }
            let next = index + 1 < tokens.count ? Self.word(tokens[index + 1]) : nil
            if let found = single(word, next) ?? phrase(word, next, tokens[(index + 1)...]) {
                return Verb(index: index, polarity: found.polarity, word: found.word)
            }
        }
        return nil
    }

    static func single(_ word: String, _ next: String?) -> (polarity: Polarity, word: String)? {
        if excludedVerbs.contains(word) { return (.excluded, word) }
        if keptVerbs.contains(word) { return (.kept, word) }
        if ["works", "work"].contains(word) { return (.works, word) }
        if word == "has", next == "no" { return (.works, "no-effect") }
        if word == "does", next == "nothing" { return (.works, "no-effect") }
        return nil
    }

    static func phrase(_ word: String, _ next: String?,
                       _ after: ArraySlice<Clause.Token>) -> (polarity: Polarity, word: String)? {
        if ["leaves", "leave", "left"].contains(word), next == "out" { return (.excluded, word) }
        if ["brings", "bring", "brought"].contains(word), after.prefix(3).contains(.word("back")) {
            return (.kept, word)
        }
        if ["shows", "show", "appears", "appear", "ends", "end"].contains(word), ["up", "in"].contains(next) {
            return (.kept, word)
        }
        if ["makes", "make", "made"].contains(word), next == "it" { return (.kept, word) }
        return nil
    }

    static func word(_ token: Clause.Token) -> String? {
        if case .word(let word) = token { word } else { nil }
    }

    static func isNegation(_ word: String) -> Bool {
        negations.contains(word) || word.hasSuffix("n't")
    }

    /// How many negations the words hold; "no longer" counts, a bare "no" ("no slash") does not.
    static func negationCount(_ words: [String]) -> Int {
        words.indices.filter { index in
            isNegation(words[index]) || words[index] == "no" && index + 1 < words.count && words[index + 1] == "longer"
        }.count
    }
}
