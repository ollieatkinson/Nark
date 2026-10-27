import Firewall
import Foundation

public struct RecordingReport: Codable, Sendable {

    public enum Status: String, Codable, Sendable {
        case recording
        case complete
        case incomplete
    }

    public struct Destination: Codable, Sendable {

        public let executable: String
        public let host: String?
        public let address: String
        public let port: String
        public let transport: String
        public let direction: Firewall.Direction
        public let localAddress: String?
        public let localPort: String?
        public var allowed: Int
        public var blocked: Int
        public var firstSeen: Date
        public var lastSeen: Date
        public var connections: Int {
            allowed + blocked
        }
    }

    public let schemaVersion: Int
    public let id: UUID
    public let application: Firewall.Application
    public let startedAt: Date
    public let endedAt: Date?
    public let status: Status
    public let observedConnections: Int
    public let allowed: Int
    public let blocked: Int
    public let missingConnections: UInt64
    public let error: String?
    public let destinations: [Destination]

    public func markdown() -> String {
        let state = "Status: **\(status.rawValue)**"
        let timeframe = "Started: \(Self.time(startedAt))\n\nEnded: \(endedAt.map(Self.time) ?? "still recording")"
        var lines = [
            "# Nark application recording",
            "",
            "Application: \(Self.cell(application.path))",
            "",
            "Scope: \(application.scope.rawValue)",
            "",
            state,
            "",
            timeframe,
            "",
            "\(observedConnections) observed connections: \(allowed) allowed, \(blocked) blocked.",
            ""
        ]
        if missingConnections > 0 {
            lines += [
                "**Incomplete: \(missingConnections) connections were lost because the provider buffer overran.**",
                ""
            ]
        }
        if let error {
            lines += ["**Recording error:** \(Self.cell(error))", ""]
        }
        lines += [
            "| Direction | Remote | Address | Port | Local port | Transport | Allowed | Blocked | First seen (UTC) | Last seen (UTC) | Executable |",
            "| --- | --- | --- | --- | --- | --- | ---: | ---: | --- | --- | --- |"
        ]
        for d in destinations {
            lines.append(
                "| \(d.direction.name) | \(Self.cell(d.host ?? d.address)) | \(Self.cell(d.address)) | \(Self.cell(d.port)) | \(Self.cell(d.localPort ?? "—")) | \(Self.cell(d.transport)) | \(d.allowed) | \(d.blocked) | \(Self.time(d.firstSeen)) | \(Self.time(d.lastSeen)) | \(Self.cell(d.executable)) |"
            )
        }
        lines += [
            "",
            "Direction identifies the connection initiator. Incoming connections are observed and allowed; blocking rules apply to outgoing connections. Local port identifies the receiving service for incoming records.",
            "",
            "Records describe new connection attempts observed during this recording. Existing connections, full URL paths, page content, and bandwidth are not captured. Hostnames may be unavailable for encrypted or opaque traffic.",
            ""
        ]
        if application.scope == .bundle {
            lines += [
                "Bundle scope includes executables inside this bundle, including nested helpers. Shared system helpers outside the bundle cannot be attributed to it by this path scope.",
                ""
            ]
        }
        return lines.joined(separator: "\n")
    }

    public static func time(_ date: Date) -> String {
        date.ISO8601Format(.init(includingFractionalSeconds: true))
    }

    private static func cell(_ value: String) -> String {
        let escaped = Set("\\|`*_[]<>#")
        return value.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map { scalar in
                let c = Character(scalar)
                return (escaped.contains(c) ? "\\" : "") + String(c)
            }
            .joined()
    }
}

/// Aggregates one session while keeping its exact flow log on disk separately.
public struct RecordingSummary {

    private struct Key: Hashable {

        let app: String
        let host: String?
        let address: String
        let port: String
        let transport: String
        let direction: Firewall.Direction
        let localAddress: String?
        let localPort: String?
    }

    private let initial: Firewall.Recording.Batch
    private var destinations: [Key: RecordingReport.Destination] = [:]
    private var endedAt: Date?
    private var failure: String?
    private var allowed = 0
    private var blocked = 0
    private var missing: UInt64 = 0
    private var lastSequence: UInt64 = 0
    public private(set) var cursor: UInt64 = 0

    public init(_ initial: Firewall.Recording.Batch) {
        self.initial = initial
    }

    public mutating func append(_ batch: Firewall.Recording.Batch) throws {
        guard batch.id == initial.id,
              batch.application == initial.application,
              batch.cursor >= cursor,
              batch.lastSequence >= batch.cursor,
              batch.startedAt == initial.startedAt else {
            throw Firewall.Error.message("Mismatched recording batch.")
        }
        var expected = cursor + 1
        let first = batch.entries.first?.sequence ?? expected
        guard first >= expected, batch.dropped == first - expected else {
            throw Firewall.Error.message("Invalid recording gap.")
        }
        expected = first
        for entry in batch.entries {
            guard entry.sequence == expected,
                  initial.application.matches(entry.connection.app) else {
                throw Firewall.Error.message("Invalid recording entry.")
            }
            expected += 1
        }
        guard batch.cursor == (batch.entries.last?.sequence ?? cursor) else {
            throw Firewall.Error.message("Invalid recording cursor.")
        }
        missing += batch.dropped
        for entry in batch.entries {
            let c = entry.connection
            let key = Key(
                app: c.app,
                host: c.host,
                address: c.address,
                port: c.port,
                transport: c.transport,
                direction: c.direction,
                localAddress: c.direction == .inbound ? c.localAddress : nil,
                localPort: c.direction == .inbound ? c.localPort : nil
            )
            var d = destinations[key] ?? RecordingReport.Destination(
                executable: c.app,
                host: c.host,
                address: c.address,
                port: c.port,
                transport: c.transport,
                direction: c.direction,
                localAddress: key.localAddress,
                localPort: key.localPort,
                allowed: 0,
                blocked: 0,
                firstSeen: entry.time,
                lastSeen: entry.time
            )
            if c.blocked {
                d.blocked += 1
                blocked += 1
            } else {
                d.allowed += 1
                allowed += 1
            }
            d.firstSeen = min(d.firstSeen, entry.time)
            d.lastSeen = max(d.lastSeen, entry.time)
            destinations[key] = d
        }
        cursor = batch.cursor
        lastSequence = batch.lastSequence
        endedAt = batch.endedAt
    }

    public mutating func fail(_ message: String, at date: Date = Date()) {
        failure = message
        endedAt = date
    }

    public var report: RecordingReport {
        RecordingReport(
            schemaVersion: 2,
            id: initial.id,
            application: initial.application,
            startedAt: initial.startedAt,
            endedAt: endedAt,
            status: failure != nil || missing > 0
                ? .incomplete
                : (endedAt == nil || cursor < lastSequence) ? .recording : .complete,
            observedConnections: allowed + blocked,
            allowed: allowed,
            blocked: blocked,
            missingConnections: missing,
            error: failure,
            destinations: destinations.values.sorted {
                if $0.connections != $1.connections {
                    return $0.connections > $1.connections
                }
                return [
                    $0.host ?? $0.address,
                    $0.executable,
                    $0.address,
                    $0.port,
                    $0.transport,
                    $0.direction.rawValue,
                    $0.localAddress ?? "",
                    $0.localPort ?? ""
                ].lexicographicallyPrecedes(
                    [
                        $1.host ?? $1.address,
                        $1.executable,
                        $1.address,
                        $1.port,
                        $1.transport,
                        $1.direction.rawValue,
                        $1.localAddress ?? "",
                        $1.localPort ?? ""
                    ]
                )
            }
        )
    }
}
