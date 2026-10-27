import ComposableArchitecture
import Firewall
import Foundation
@testable import Monitor
import Testing
import TestSupport
import Vocabulary

@Suite @MainActor struct ConnectionQueryTests {

    private func rows() -> [Firewall.Connection] {
        let helper = Firewall.Connection(
            app: "/Applications/Example Browser.app/Contents/Helpers/Network Service",
            host: "api.example.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        var main = helper
        main.id = UUID()
        main.app = "/Applications/Example Browser.app/Contents/MacOS/Main"
        main.host = "incoming.mail.test"
        main.address = "192.0.2.2"
        main.port = "80"
        main.transport = "UDP"
        main.direction = .inbound
        main.localAddress = "192.168.1.2"
        main.localPort = "8080"
        var other = helper
        other.id = UUID()
        other.app = "/Applications/Other.app/Contents/MacOS/Network Service"
        other.host = "elsewhere.test"
        return [helper, main, other]
    }

    @Test func field_choices_distinguish_app_service_endpoints_and_current_policy() {
        let rows = rows()
        let cases: [(ConnectionQuery.Field, String, [Int])] = [
            (.all, "example", [0, 1]),
            (.app, "Example Browser", [0, 1]),
            (.app, "Network Service", []),
            (.service, "Network Service", [0, 2]),
            (.service, "Example Browser", []),
            (.remote, "api.example", [0]),
            (.remote, "192.0.2.1", [0, 2]),
            (.local, "8080", [1]),
            (.port, "443", [0, 2]),
            (.type, "udp", [1]),
            (.dir, "incoming", [1]),
            (.dir, "↗", [0, 2]),
            (.policy, "block", [0]),
            (.policy, "allow", [1, 2]),
        ]
        for (field, text, expected) in cases {
            let filter = ConnectionQuery(text, field: field)
            let matches = rows.indices.filter { index in
                filter.matches(
                    rows[index],
                    isBlocked: { index == 0 }
                )
            }
            #expect(matches == expected, "\(field):\(text)")
        }
    }

    @Test func qualified_terms_combine_support_spaces_and_accept_partial_input() {
        let rows = rows()
        for text in [
            "app:\"Example Browser\" service:\"Network Service\" remote:api.example port:443 type:tcp dir:out policy:block",
            "application:\"Example Browser\" process:\"Network Service\" domain:api.example protocol:tcp direction:outbound",
            "service:\"Network Ser remote:unused", // An unfinished quoted value is literal, not another term.
        ] {
            let matches = rows.indices.filter { index in
                ConnectionQuery(text).matches(
                    rows[index],
                    isBlocked: { index == 0 }
                )
            }
            #expect(matches == (text.hasSuffix("unused") ? [] : [0]))
        }
        #expect(ConnectionQuery("service:\"Network Ser").matches(rows[0], isBlocked: { false }))
        #expect(ConnectionQuery("incoming").matches(rows[1], isBlocked: { false }))
        #expect(ConnectionQuery("remote:incoming.mail").matches(rows[1], isBlocked: { false }))
        #expect(ConnectionQuery("  ").matches(rows[0], isBlocked: { false }))
        #expect(ConnectionQuery("remote:").matches(rows[0], isBlocked: { false }))
        var lookups = 0
        #expect(ConnectionQuery("api.example").matches(
            rows[0],
            isBlocked: {
                lookups += 1
                return false
            }
        ))
        #expect(lookups == 0)
    }

    @Test func list_keeps_app_scope_through_zero_results_refresh_and_clear() async throws {
        let rows = rows()
        let runtime = try Firewall.Runtime()
        var state = MonitorFeature.State()
        state.snapshot = .init(rows: rows)
        let app = try #require(state.activityTree.nodes.values.first { $0.title == "Example Browser" })
        state.home.selection = app.id
        state.page = .activity
        let store = TestStore(initialState: state) {
            MonitorFeature(client: .init(runtime: runtime))
        }
        await store.send(.selectSearchField(.service)) { $0.searchField = .service }
        await store.send(.search("no-such-service")) {
            $0.query = "no-such-service"
            $0.blocklists.query = "no-such-service"
        }
        #expect(store.state.rows.isEmpty)
        #expect(store.state.home.selection == app.id)
        await store.send(.received(.init(rows: rows, startedAt: state.snapshot.startedAt))) {
            $0.connected = true
        }
        #expect(store.state.home.selection == app.id)
        await store.send(.search("Network Service")) {
            $0.query = "Network Service"
            $0.blocklists.query = "Network Service"
        }
        #expect(store.state.rows.map(\.id) == [rows[0].id])
        await store.send(.search("")) {
            $0.query = ""
            $0.blocklists.query = ""
        }
        #expect(Set(store.state.rows.map(\.id)) == Set(rows.prefix(2).map(\.id)))
    }

    @Test func selection_and_cycle_use_inherited_lexicon_events() throws {
        let select = Event(nark.ux.monitor.search.field["remote"].event.select)
        guard case .selectSearchField(.remote) = MonitorFeature.Session.action(for: select) else {
            Issue.record("Select lost its field context")
            return
        }
        let move = Event(nark.ux.monitor.search.field[1].event.move)
        guard case .moveSearchField(1) = MonitorFeature.Session.action(for: move) else {
            Issue.record("Select lost its move context")
            return
        }
    }
}
