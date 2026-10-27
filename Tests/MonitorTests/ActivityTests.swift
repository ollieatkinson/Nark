import ComposableArchitecture
import Control
import Firewall
import Foundation
@testable import Monitor
import Testing
import TestSupport
import Vocabulary

@Suite @MainActor struct ActivityTests {

    @Test func rates_use_elapsed_time_reset_on_provider_replacement_and_sort_recent_apps() {
        let a = Firewall.Connection(
            app: "/A",
            host: nil,
            address: "8.8.8.8",
            port: "443",
            transport: "TCP",
            blocked: false,
            count: 1000
        )
        var b = a
        b.id = UUID()
        b.app = "/B"
        b.count = 1
        var traffic = Firewall.Traffic()
        traffic.applications["/A"] = .init(received: 100, sent: 50)
        var snapshot = Firewall.Snapshot(rows: [a, b], traffic: traffic)
        var state = MonitorFeature.State()
        let start = Date(timeIntervalSince1970: 100)
        state.activity.record(snapshot, at: start)
        snapshot.rows[1].count = 11
        snapshot.traffic?.applications["/B"] = .init(received: 2000, sent: 1000)
        state.activity.record(snapshot, at: start.addingTimeInterval(2))
        state.snapshot = snapshot
        #expect(state.applications.map(\.path) == ["/B", "/A"])
        #expect(state.trafficSamples.last?.received == 1000)
        state.selectedApplication = "/A"
        #expect(state.trafficSamples.last?.received == 0)
        snapshot.traffic = Firewall.Traffic()
        state.activity.record(snapshot, at: start.addingTimeInterval(3))
        #expect(state.activity.count == 0)
        for second in 4 ... 350 {
            state.activity.record(
                snapshot,
                at: start.addingTimeInterval(Double(second))
            )
        }
        #expect(state.activity.count == 300)
        #expect(state.activity.applications.values.allSatisfy { $0.count == 300 })
    }

    @Test func detail_activation_survives_reordering_and_back_retains_selection() async throws {
        let runtime = try Firewall.Runtime()
        let a = Firewall.Connection(
            app: "/A",
            host: "one.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        var b = a
        b.id = UUID()
        b.app = "/B"
        var initial = MonitorFeature.State()
        initial.snapshot = Firewall.Snapshot(rows: [a, b])
        initial.selection = 1
        initial.connected = true
        let store = TestStore(initialState: initial) {
            MonitorFeature(client: .init(runtime: runtime))
        }
        let event = Event(nark.ux.monitor.connections.row[b.id.uuidString].event.activate)
        guard case .openConnection(let id) = MonitorFeature.Session.action(for: event) else {
            Issue.record("Missing inherited activation")
            return
        }
        await store.send(.openConnection(id)) { $0.detail = b }
        let updated = Firewall.Snapshot(rows: [b, a])
        await store.send(.received(updated)) {
            $0.snapshot = updated
            $0.selection = 0
        }
        await store.send(.closeDetail) { $0.detail = nil }
        #expect(store.state.selectedConnection?.id == b.id)
    }
}
