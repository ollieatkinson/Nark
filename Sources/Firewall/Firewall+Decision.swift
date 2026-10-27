import Foundation
import Vocabulary

extension Firewall {

    public struct Decision: Codable, Hashable, Sendable {

        public enum Verdict: String, Codable, Sendable {
            case allow
            case drop
        }

        public var verdict: Verdict
        public var rule: UUID?
        public var blocklist: UUID?
        public init(verdict: Verdict, rule: UUID? = nil, blocklist: UUID? = nil) {
            self.verdict = verdict
            self.rule = rule
            self.blocklist = blocklist
        }
    }
}

extension Firewall.Connection {

    /// The runtime publishes the same composed concept the provider evaluates.
    /// SwiftLexicon owns delivery, buffering, matching, and observation lifetime.
    public func event(decision: Firewall.Decision) throws -> Event {
        let flow = try nark.filter.flow.encoding(self)
        switch decision.verdict {
            case .allow:
                return Event(try flow.decision.encoding(decision).verdict.allow)
            case .drop:
                return Event(try flow.decision.encoding(decision).verdict.drop)
        }
    }
}
