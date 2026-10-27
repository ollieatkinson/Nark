@testable import Firewall
import Foundation
import Testing

@Suite struct IdentityTests {

    @Test func reused_flow_ids_produce_distinct_stable_aggregate_ids() {
        let first = connection(host: "one.test", count: 3)
        var second = first
        second.host = "two.test"
        second.count = 5
        let snapshot = Firewall.Snapshot(rows: [first, second])
        let normalized = snapshot.normalizingConnectionIDs()
        #expect(Set(normalized.rows.map(\.id)).count == 2)
        let reversed = Firewall.Snapshot(rows: [second, first]).normalizingConnectionIDs(previous: normalized)
        #expect(normalized.rows[0].id == reversed.rows[1].id)
        #expect(normalized.rows[1].id == reversed.rows[0].id)
        let remaining = Firewall.Snapshot(rows: [second]).normalizingConnectionIDs(previous: reversed)
        #expect(remaining.rows[0].id == normalized.rows[1].id)
        #expect(normalized.normalizingConnectionIDs().rows == normalized.rows)
    }

    @Test func identical_legacy_rows_merge_counts_and_bytes_without_losing_the_list_match() {
        var row = connection(host: "one.test", count: 3)
        row.traffic = .init(received: 10, sent: 5)
        var snapshot = Firewall.Snapshot(rows: [row, row])
        let list = UUID()
        snapshot.blocklistMatches = [row.id.uuidString: list]
        let normalized = snapshot.normalizingConnectionIDs()
        #expect(normalized.rows.count == 1)
        #expect(normalized.rows[0].count == 6)
        #expect(normalized.rows[0].traffic == .init(received: 20, sent: 10))
        #expect(normalized.blocklistMatches?[normalized.rows[0].id.uuidString] == list)
    }

    @Test func the_provider_does_not_reuse_a_flow_id_for_a_new_aggregate() throws {
        let runtime = try Firewall.Runtime()
        let first = connection(host: "one.test", count: 1)
        var second = first
        second.host = "two.test"
        runtime.record(first)
        runtime.record(second)
        runtime.record(second)
        let rows = runtime.snapshot().rows
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.id)).count == 2)
        #expect(rows.first?.count == 2)
    }

    private func connection(host: String, count: Int) -> Firewall.Connection {
        .init(
            app: "/usr/bin/example",
            host: host,
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false,
            count: count
        )
    }
}
