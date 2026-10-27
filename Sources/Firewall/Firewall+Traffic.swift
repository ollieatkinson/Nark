import Foundation

extension Firewall {

    /// Byte counters supplied by Network Extension, for flows observed in this provider session.
    public struct Traffic: Codable, Equatable, Sendable {

        public struct Bytes: Codable, Hashable, Sendable {

            public var received: Int64
            public var sent: Int64
            public init(received: Int64 = 0, sent: Int64 = 0) {
                self.received = received
                self.sent = sent
            }

            public static func + (lhs: Self, rhs: Self) -> Self {
                Self(received: lhs.received + rhs.received, sent: lhs.sent + rhs.sent)
            }
        }

        public var session = UUID()
        public var applications: [String: Bytes] = [:]
        public var untrackedFlows = 0
        public init() {}
        public var total: Bytes {
            applications.values.reduce(Bytes(), +)
        }
    }

    /// Reports contain cumulative per-flow counters. Retaining the previous value prevents
    /// a final close report from counting the last statistics report twice.
    struct TrafficTracker: Sendable {

        struct Flow: Sendable {

            let connection: Connection
            var bytes = Traffic.Bytes()
            var updatedAt = Date()
        }

        var flows: [UUID: Flow] = [:]
        var summary = Traffic()
        mutating func observe(_ row: Connection) {
            guard !row.blocked, flows[row.id] == nil else {
                return
            }
            guard summary.applications[row.app] != nil || summary.applications.count < 4096 else {
                summary.untrackedFlows += 1
                return
            }
            if summary.applications[row.app] == nil {
                summary.applications[row.app] = .init()
            }
            if
                flows.count >= 32_768,
                let oldest = flows.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key
            {
                flows.removeValue(forKey: oldest)
                summary.untrackedFlows += 1
            }
            flows[row.id] = Flow(connection: row)
        }

        mutating func report(
            id: UUID,
            received: Int64,
            sent: Int64,
            closed: Bool
        ) -> (Connection, Traffic.Bytes)? {
            guard var flow = flows[id] else {
                return nil
            }
            guard
                summary.applications[flow.connection.app] != nil || summary.applications
                    .count < 4096
            else {
                flows.removeValue(forKey: id)
                summary.untrackedFlows += 1
                return nil
            }
            // Ignore regressing or repeated counters; never turn a reset into a traffic spike.
            let delta = Traffic.Bytes(
                received: max(0, received - flow.bytes.received),
                sent: max(0, sent - flow.bytes.sent)
            )
            flow.bytes.received = max(flow.bytes.received, received)
            flow.bytes.sent = max(flow.bytes.sent, sent)
            flow.updatedAt = Date()
            if closed {
                flows.removeValue(forKey: id)
            } else {
                flows[id] = flow
            }
            summary.applications[flow.connection.app, default: .init()] = summary.applications[
                flow.connection.app,
                default: .init()
            ] + delta
            return (flow.connection, delta)
        }

        mutating func clear() {
            summary = Traffic()
        }
    }
}
