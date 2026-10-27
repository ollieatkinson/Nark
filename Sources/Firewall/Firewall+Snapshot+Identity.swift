import CryptoKit
import Foundation

extension Firewall.Snapshot {

    /// Older providers could reuse a flow UUID for different aggregate rows.
    /// Repair every occurrence of a reused UUID, independently of row ordering.
    public func normalizingConnectionIDs(previous: Self? = nil) -> Self {
        let counts = Dictionary(grouping: rows, by: \.id).mapValues(\.count)
        guard previous != nil || counts.values.contains(where: { $0 > 1 }) else {
            return self
        }
        var result = self
        var normalized: [Firewall.Connection] = []
        var positions: [UUID: Int] = [:]
        let previousIDs = Set(previous?.rows.map(\.id) ?? [])
        for var row in rows {
            let original = row.id
            if counts[original, default: 0] > 1 || !previousIDs.isEmpty {
                let fields = [
                    original.uuidString,
                    row.app,
                    row.host ?? "",
                    row.address,
                    row.port,
                    row.transport,
                    row.direction.rawValue,
                    row.localAddress ?? "",
                    row.localPort ?? "",
                    row.blocked ? "blocked" : "allowed"
                ]
                let key = fields.map { "\($0.utf8.count):\($0)" }.joined()
                var digest = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
                digest[6] = (digest[6] & 0x0f) | 0x80
                digest[8] = (digest[8] & 0x3f) | 0x80
                let identity = UUID(uuid: (
                    digest[0],
                    digest[1],
                    digest[2],
                    digest[3],
                    digest[4],
                    digest[5],
                    digest[6],
                    digest[7],
                    digest[8],
                    digest[9],
                    digest[10],
                    digest[11],
                    digest[12],
                    digest[13],
                    digest[14],
                    digest[15]
                ))
                if counts[original, default: 0] > 1 || previousIDs.contains(identity) {
                    row.id = identity
                    if let match = blocklistMatches?[original.uuidString] {
                        result.blocklistMatches?[row.id.uuidString] = match
                    }
                }
            }
            if let position = positions[row.id] {
                normalized[position].count += row.count
                normalized[position].lastSeen = max(normalized[position].lastSeen, row.lastSeen)
                if let traffic = row.traffic {
                    normalized[position].traffic = (normalized[position].traffic ?? .init()) + traffic
                }
            } else {
                positions[row.id] = normalized.count
                normalized.append(row)
            }
        }
        result.rows = normalized
        return result
    }
}
