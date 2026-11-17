import DockerignoreClaimKit
import GitignoreClaimKit

/// Prints a heading for a scenario.
func scenario(_ number: Int, _ title: String) {
    print("")
    print("== \(number). \(title)")
}

/// Prints an answer's report: its verdict, a summary line and one line per finding.
func show(_ label: String, _ report: DockerignoreReport) {
    print("-- \(label): \(report.verdict.rawValue) (\(report.summary))")
    for finding in report.findings {
        let mark = switch finding.severity {
        case .holds: "ok   "
        case .unchecked: "skip "
        case .caution: "check"
        case .wrong: "WRONG"
        }
        let repeated = finding.isRepeated ? " [repeated]" : ""
        print("   \(mark) \(finding.claim.kind.rawValue): \(finding.explanation)\(repeated)")
    }
}

/// Prints one line of Docker's verdict for a path.
func explain(_ rules: DockerignoreRules, _ path: String, builder: DockerBuilder = .classic) {
    let verdict = rules.verdict(for: path, builder: builder)
    let line = verdict.decidingPattern.map { " <- `\($0.line)` (line \($0.lineNumber))" } ?? ""
    let skipped = verdict.skippedDirectory.map { " via skipped \($0)" } ?? ""
    print("   \(verdict.isExcluded ? "left out" : "sent    ")  \(path)\(line)\(skipped)")
}

/// Prints git's verdict and Docker's for the same lines and path.
func compare(_ text: String, _ path: String) {
    let git = IgnoreRules(text).verdict(for: path).isIgnored ? "ignored" : "kept   "
    let docker = DockerignoreRules(text).verdict(for: path).isExcluded ? "left out" : "sent    "
    print("   as .gitignore: \(git)   as .dockerignore: \(docker)  \(path)")
}
