@testable import DockerignoreClaimKit
import Testing

struct ParityCase: Sendable {
    let name: String
    let ignore: String
    let buildFails: Bool
    let paths: [String: Bool]
}

@Suite("Parity with docker build")
struct ParityTests {
    @Test("every path the classic builder sent, or left out, is decided the same way", arguments: ParityFixture.cases)
    func parity(_ fixture: ParityCase) {
        let rules = DockerignoreRules(fixture.ignore)
        #expect((rules.problem?.problem == .malformed) == fixture.buildFails, "\(fixture.name)")
        for (path, included) in fixture.paths {
            #expect(rules.verdict(for: path, builder: .classic).isExcluded == !included, "\(fixture.name): \(path)")
        }
    }
}
