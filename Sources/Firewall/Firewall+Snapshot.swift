import Foundation

extension Firewall {

    public struct Snapshot: Codable, Equatable, Sendable {

        public var rows: [Firewall.Connection]
        public var rules: [Firewall.Rule]
        public var startedAt: Date
        public var totalAllowed: Int
        public var totalBlocked: Int
        public var traffic: Firewall.Traffic?
        public var blocklists: [Firewall.Blocklist.Summary]?
        public var blocklistMatches: [String: UUID]?
        public init(
            rows: [Firewall.Connection] = [], rules: [Firewall.Rule] = [], startedAt: Date = Date(),
            totalAllowed: Int = 0, totalBlocked: Int = 0, traffic: Firewall.Traffic? = nil
        ) {
            self.rows = rows
            self.rules = rules
            self.startedAt = startedAt
            self.totalAllowed = totalAllowed
            self.totalBlocked = totalBlocked
            self.traffic = traffic
            blocklists = nil
            blocklistMatches = nil
        }
    }
}

extension Firewall.Snapshot {

    public func blocks(_ connection: Firewall.Connection) -> Bool {
        guard connection.direction == .outbound else {
            return false
        }
        return blocklistMatches?[connection.id.uuidString] != nil
            || rules.contains { $0.matches(
                app: connection.app,
                host: connection.host,
                address: connection.address,
                direction: connection.direction
            ) }
    }
}
