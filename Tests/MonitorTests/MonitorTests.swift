import ComposableArchitecture
import Control
import Firewall
import Foundation
import IssueReportingTestSupport
@testable import Monitor
import Testing
import TestSupport
import Vocabulary

@Suite @MainActor struct MonitorTests {

    @Test func composed_feature_controls_route_values_from_their_owning_component() {
        let application = Event(nark.ux.monitor.applications.row["/usr/bin/curl"].event.select)
        guard case .selectApplication(let path) = MonitorFeature.Session.action(for: application) else {
            Issue.record("Application selection did not route")
            return
        }
        #expect(path == "/usr/bin/curl")
        let id = UUID()
        let connection = Event(nark.ux.monitor.connections.row[id.uuidString].event.select)
        guard case .selectConnection(let selected, let event) = MonitorFeature.Session.action(for: connection) else {
            Issue.record("Connection selection did not route")
            return
        }
        #expect(selected == id)
        #expect(event == connection.id)
        let search = Event(nark.ux.monitor.search["example.com"].event.change)
        guard case .search(let query) = MonitorFeature.Session.action(for: search) else {
            Issue.record("Search did not route")
            return
        }
        #expect(query == "example.com")
        let add = Event(nark.ux.monitor.rules.add["example.com"].event.select)
        guard case .addDomain(let domain) = MonitorFeature.Session.action(for: add) else {
            Issue.record("Rule creation did not route")
            return
        }
        #expect(domain == "example.com")
        #expect(MonitorFeature.Session.action(for: Event(nark.ui.component.application.event.select)) == nil)
        #expect(
            MonitorFeature.Session.action(for: Event(nark.ux.monitor.connections.row["invalid"].event.select)) == nil
        )
    }

    @Test func application_focus_includes_nested_helpers_and_relevant_rules_only() throws {
        var state = MonitorFeature.State()
        state.application = try Firewall.Application(
            path: "/Applications/Example.app",
            scope: .bundle
        )
        let main = Firewall.Connection(
            app: "/Applications/Example.app/Contents/MacOS/Main",
            host: "main.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        var helper = main
        helper.id = UUID()
        helper.app = "/Applications/Example.app/Contents/Helpers/Helper"
        var other = main
        other.id = UUID()
        other.app = "/Applications/Other.app/Contents/MacOS/Main"
        let global = try Firewall.Rule(domain: "global.test")
        let own = try Firewall.Rule(app: main.app)
        let unrelated = try Firewall.Rule(app: other.app)
        state.snapshot = Firewall.Snapshot(
            rows: [main, helper, other],
            rules: [global, own, unrelated]
        )
        #expect(state.rows.map(\.id) == [main.id, helper.id])
        #expect(state.rules.map(\.id) == [global.id, own.id])
        state.selectedApplication = helper.app
        #expect(state.rows.map(\.id) == [helper.id])
        state.query = "Other"
        #expect(state.rows.isEmpty)
    }

    @Test func refresh_preserves_selected_connection_when_activity_reorders() async throws {
        let runtime = try Firewall.Runtime()
        let first = Firewall.Connection(
            app: "/first",
            host: "one.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        let selected = Firewall.Connection(
            app: "/selected",
            host: "two.test",
            address: "192.0.2.2",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        var initial = MonitorFeature.State()
        initial.snapshot = Firewall.Snapshot(rows: [first, selected])
        initial.selection = 1
        initial.connected = true
        let store = TestStore(initialState: initial) {
            MonitorFeature(client: .init(runtime: runtime))
        }
        let refreshed = Firewall.Snapshot(rows: [selected, first])
        await store.send(.received(refreshed)) {
            $0.snapshot = refreshed
            $0.selection = 0
        }
    }

    @Test func block_selected_destination_reaches_policy_and_rule_can_be_removed() async throws {
        let runtime = try Firewall.Runtime()
        runtime.record(
            Firewall.Connection(
                app: "/usr/bin/curl",
                host: "example.com",
                address: "192.0.2.1",
                port: "443",
                transport: "TCP",
                blocked: false
            )
        )
        var initial = MonitorFeature.State()
        initial.page = .activity
        let store = TestStore(initialState: initial) {
            MonitorFeature(client: .init(runtime: runtime))
        }
        let original = runtime.snapshot()
        await store.send(.received(original)) {
            $0.snapshot = original
            $0.connected = true
        }
        await store.send(.blockDestination) { $0.busy = true }
        // UUID is generated inside the feature; capture the actual provider result.
        await store.receive(\.prepareSnapshot)
        await store.receive(\.received) {
            $0.snapshot = runtime.snapshot()
            $0.busy = false
        }
        #expect(runtime.isBlocked(app: "/other", host: "sub.example.com", address: "192.0.2.1"))
        await store.send(.switchView) { $0.rulesVisible = true }
        await store.send(.removeRule) { $0.busy = true }
        await store.receive(\.prepareSnapshot)
        await store.receive(\.received) {
            $0.snapshot = runtime.snapshot()
            $0.busy = false
        }
        #expect(runtime.snapshot().rules.isEmpty)
    }

    @Test func disconnected_provider_surfaces_error_and_retry_recovers() async throws {
        let store = TestStore(initialState: MonitorFeature.State()) {
            MonitorFeature(
                client: Firewall.Client(
                    request: { _ in
                        throw Firewall.Error.message("offline")
                    }
                )
            )
        }
        await store.send(.refresh) { $0.busy = true }
        await store.receive(\.failed) {
            $0.busy = false
            $0.error = "offline"
        }
        let snapshot = Firewall.Snapshot()
        await store.send(.received(snapshot)) {
            $0.snapshot = snapshot
            $0.error = nil
            $0.connected = true
        }
    }
}
