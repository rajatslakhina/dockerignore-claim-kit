/// A way of misreading .dockerignore rules. Checking a wrong claim under each one names the mistake behind it: if
/// the claim holds once `*.log` is read as matching at every level, the answer applied .gitignore's rule.
struct Reading: OptionSet, Sendable, Hashable {
    let rawValue: Int

    /// `node_modules  # deps` read as `node_modules` plus a comment.
    static let trailingComments = Reading(rawValue: 1 << 0)
    /// `*.log` or `node_modules` read as matching at every level, the way .gitignore reads a pattern with no slash.
    static let slashlessAnyDepth = Reading(rawValue: 1 << 1)
    /// An exception read as unable to bring back a path below an excluded directory, the way git behaves.
    static let excludedParentIsFinal = Reading(rawValue: 1 << 2)
    /// `doc/*.txt` read as matching `doc/a/b.txt`.
    static let starCrossesSlash = Reading(rawValue: 1 << 3)
    /// The first matching line read as deciding, instead of the last.
    static let firstMatchWins = Reading(rawValue: 1 << 4)
    /// `[!a]` read as "any character but `a`", the way a shell glob reads it.
    static let bangNegates = Reading(rawValue: 1 << 6)
    /// Letters read as matching without regard to case.
    static let ignoreCase = Reading(rawValue: 1 << 5)
}
