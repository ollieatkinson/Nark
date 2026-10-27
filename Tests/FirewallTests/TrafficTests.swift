@testable import Firewall
import Foundation
import Testing

@Test func traffic_reports_accumulate_deltas_once_and_keep_aggregate_identity() throws {
    let runtime = try Firewall.Runtime()
    let first = Firewall.Connection(
        app: "/app",
        host: "test.example",
        address: "192.0.2.1",
        port: "443",
        transport: "TCP",
        blocked: false
    )
    var second = first
    second.id = UUID()
    _ = runtime.evaluate(first)
    _ = runtime.evaluate(second)
    runtime.reportTraffic(id: first.id, received: 100, sent: 50, closed: false)
    runtime.reportTraffic(id: first.id, received: 200, sent: 60, closed: false)
    runtime.reportTraffic(id: first.id, received: 150, sent: 40, closed: false)
    runtime.reportTraffic(id: first.id, received: 200, sent: 60, closed: true)
    runtime.reportTraffic(id: first.id, received: 200, sent: 60, closed: true)
    runtime.reportTraffic(id: second.id, received: 20, sent: 10, closed: true)
    let snapshot = runtime.snapshot()
    #expect(snapshot.rows.count == 1)
    #expect(snapshot.rows[0].id == first.id)
    #expect(snapshot.rows[0].count == 2)
    #expect(snapshot.rows[0].traffic == .init(received: 220, sent: 70))
    #expect(snapshot.traffic?.total == .init(received: 220, sent: 70))
    #expect(snapshot.totalAllowed == 2)
}

@Test func old_checkpoints_decode_without_new_traffic_fields() throws {
    let runtime = try Firewall.Runtime()
    runtime.record(Firewall.Connection(
        app: "/app",
        host: nil,
        address: "192.0.2.1",
        port: "443",
        transport: "TCP",
        blocked: false
    ))
    var object = try #require(JSONSerialization
        .jsonObject(with: JSONEncoder().encode(runtime.snapshot())) as? [String: Any])
    object.removeValue(forKey: "traffic")
    let decoded = try JSONDecoder().decode(
        Firewall.Snapshot.self,
        from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(decoded.rows.count == 1)
    #expect(decoded.traffic == nil)
    #expect(decoded.rows[0].traffic == nil)
}
