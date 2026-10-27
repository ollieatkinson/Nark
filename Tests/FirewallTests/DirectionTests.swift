import Firewall
import Foundation
import Testing

@Suite struct DirectionTests {

    private func connection(_ direction: Firewall.Direction, port: String = "8080") -> Firewall.Connection {
        .init(
            app: "/app",
            host: "peer.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false,
            direction: direction,
            localAddress: "192.0.2.2",
            localPort: port
        )
    }

    @Test func legacy_history_remains_outgoing_and_new_endpoints_round_trip() throws {
        let row = connection(.inbound)
        let data = try JSONEncoder().encode(row)
        #expect(try JSONDecoder().decode(Firewall.Connection.self, from: data) == row)
        var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["direction", "localAddress", "localPort"] {
            old.removeValue(forKey: key)
        }
        let restored = try JSONDecoder().decode(
            Firewall.Connection.self,
            from: JSONSerialization.data(withJSONObject: old)
        )
        #expect(restored.direction == .outbound)
        #expect(restored.localPort == nil)
        #expect(restored.id == row.id)
        #expect(restored.count == row.count)
    }

    @Test func directions_and_receiving_service_ports_keep_separate_counts_and_byte_reports(
    ) throws {
        let runtime = try Firewall.Runtime()
        let outgoing = connection(.outbound)
        let incoming = connection(.inbound)
        let secondService = connection(.inbound, port: "9090")
        for row in [outgoing, incoming, secondService] {
            _ = runtime.evaluate(row)
        }
        runtime.reportTraffic(id: outgoing.id, received: 100, sent: 20, closed: true)
        runtime.reportTraffic(id: incoming.id, received: 30, sent: 200, closed: true)
        runtime.reportTraffic(id: secondService.id, received: 40, sent: 300, closed: true)
        let snapshot = runtime.snapshot()
        #expect(snapshot.rows.count == 3)
        #expect(snapshot.rows.first { $0.id == outgoing.id }?.traffic == .init(
            received: 100,
            sent: 20
        ))
        #expect(snapshot.rows.first { $0.id == incoming.id }?.traffic == .init(
            received: 30,
            sent: 200
        ))
        #expect(snapshot.rows.first { $0.id == secondService.id }?.localPort == "9090")
        #expect(snapshot.traffic?.total == .init(received: 170, sent: 520))
        // Outgoing ephemeral local ports do not fragment destination history.
        _ = runtime.evaluate(connection(.outbound, port: "60000"))
        #expect(runtime.snapshot().rows.count == 3)
        #expect(runtime.snapshot().rows.first { $0.direction == .outbound }?.count == 2)
        #expect(runtime.snapshot().rows.first { $0.direction == .outbound }?.localPort == "60000")
    }

    @Test func incoming_and_unknown_directions_are_observed_without_applying_manual_rules_or_lists(
    ) throws {
        let runtime = try Firewall.Runtime()
        _ = runtime.handle(.add(try Firewall.Rule(app: "/app")))
        let imported = runtime.handle(
            .blocklist(
                .replace(
                    .init(
                        name: "Direction fixture",
                        source: "/directions.txt",
                        text: "peer.test"
                    )
                )
            )
        )
        let list = try #require(imported.snapshot?.blocklists?.first { $0.name == "Direction fixture" })
        #expect(runtime.handle(.blocklist(.toggle(list.id))).error == nil)
        for direction in [Firewall.Direction.inbound, .unknown, .outbound] {
            let row = connection(direction)
            let decision = runtime.evaluate(row)
            #expect(decision.verdict == (direction == .outbound ? .drop : .allow))
            #expect(runtime.snapshot().blocks(row) == (direction == .outbound))
            #expect((runtime.snapshot().blocklistMatches?[row.id.uuidString] != nil) == (direction == .outbound))
        }
        #expect(runtime.snapshot().totalAllowed == 2)
        #expect(runtime.snapshot().totalBlocked == 1)
        let rule = try Firewall.Rule(app: "/app")
        #expect(!rule.matches(app: "/app", host: nil, address: "192.0.2.1", direction: .inbound))
    }
}
