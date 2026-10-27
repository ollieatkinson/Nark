import Foundation

extension Firewall {

    public enum Recording {

        public enum Request: Codable, Sendable {
            case start(Application)
            case read(Cursor)
            case stop(Cursor)
            case close(UUID)
        }

        public struct Cursor: Codable, Hashable, Sendable {

            public let id: UUID
            public let after: UInt64
            public init(id: UUID, after: UInt64) {
                self.id = id
                self.after = after
            }
        }

        public struct Entry: Codable, Equatable, Sendable {

            public let sequence: UInt64
            public let time: Date
            public let connection: Connection
            public init(sequence: UInt64, time: Date, connection: Connection) {
                self.sequence = sequence
                self.time = time
                self.connection = connection
            }
        }

        public struct Batch: Codable, Sendable {

            public let id: UUID
            public let application: Application
            public let startedAt: Date
            public let endedAt: Date?
            public let entries: [Entry]
            public let cursor: UInt64
            public let lastSequence: UInt64
            public let dropped: UInt64
            public var hasMore: Bool {
                cursor < lastSequence
            }
        }
    }
}

extension Firewall.Recording {

    /// The provider keeps a bounded ring; clients drain it into their own durable log.
    /// Recording never waits for disk I/O or for a client to consume an entry.
    struct Session: Sendable {

        static let capacity = 4096
        static let batchSize = 256
        static let lease: TimeInterval = 60
        let id: UUID
        let application: Firewall.Application
        let startedAt: Date
        var endedAt: Date?
        var lastReadAt: Date
        private(set) var sequence: UInt64 = 0
        private var ring: [Entry] = []

        init(application: Firewall.Application, now: Date) {
            id = UUID()
            self.application = application
            startedAt = now
            lastReadAt = now
        }

        func expired(at now: Date) -> Bool {
            now.timeIntervalSince(lastReadAt) > Self.lease
        }

        mutating func record(_ connection: Firewall.Connection, at now: Date) {
            guard endedAt == nil, application.matches(connection.app) else {
                return
            }
            sequence += 1
            var connection = connection
            connection.count = 1
            let entry = Entry(sequence: sequence, time: now, connection: connection)
            if ring.count < Self.capacity {
                ring.append(entry)
            } else {
                ring[Int((sequence - 1) % UInt64(Self.capacity))] = entry
            }
        }

        mutating func read(after: UInt64, at now: Date) throws -> Batch {
            guard after <= sequence else {
                throw Firewall.Error.message("Invalid recording cursor.")
            }
            lastReadAt = now
            let earliest = sequence >= UInt64(Self.capacity) ? sequence - UInt64(Self.capacity) + 1 : 1
            let first = max(after + 1, earliest)
            let dropped = first - after - 1
            let last = min(sequence, first + UInt64(Self.batchSize) - 1)
            let entries: [Entry] = first <= last
                ? (first ... last).map { ring[Int(($0 - 1) % UInt64(Self.capacity))] }
                : []
            return Batch(
                id: id,
                application: application,
                startedAt: startedAt,
                endedAt: endedAt,
                entries: entries,
                cursor: entries.last?.sequence ?? after,
                lastSequence: sequence,
                dropped: dropped
            )
        }
    }
}
