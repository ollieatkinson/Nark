import ComposableArchitecture
import Control
import Firewall
import Foundation
@testable import Monitor
import Testing
import TestSupport
import Vocabulary

@Suite @MainActor struct ActivityTreeTests {

    @Test(arguments: [MonitorFeature.Page.home, .activity])
    func selecting_all_clears_every_application_scope_without_leaving_the_page(page: MonitorFeature.Page) async throws {
        let first = connection(
            "/Applications/First.app/Contents/MacOS/Main",
            host: "peer.test",
            address: "192.0.2.1"
        )
        let second = connection(
            "/Applications/Second.app/Contents/MacOS/Main",
            host: "peer.test",
            address: "192.0.2.2"
        )
        var initial = MonitorFeature.State()
        initial.snapshot = .init(rows: [first, second])
        initial.application = try .init(path: "/Applications/First.app", scope: .bundle)
        initial.selectedApplication = first.app
        let app = try #require(initial.activityTree.roots.first)
        initial.home.selection = app
        initial.home.expanded = [app]
        initial.query = "peer"
        initial.searchField = .remote
        initial.page = page
        let runtime = try Firewall.Runtime()
        let store = TestStore(initialState: initial) {
            MonitorFeature(client: .init(runtime: runtime))
        }
        await store.send(.selectNode(ActivityTree.all)) {
            $0.home.selection = ActivityTree.all
            $0.application = nil
            $0.selectedApplication = nil
        }
        #expect(store.state.page == page)
        #expect(store.state.query == "peer")
        #expect(store.state.searchField == .remote)
        #expect(Set(store.state.rows.map(\.id)) == [first.id, second.id])
        #expect(store.state.home.expanded == [app])
    }

    @Test func home_policy_changes_without_new_traffic_and_preserves_observed_verdicts() throws {
        var first = connection(
            "/Applications/Example.app/Contents/MacOS/Main",
            host: "one.test",
            address: "192.0.2.1",
            count: 3
        )
        first.blocked = true // Historical verdict must not keep a disabled rule red.
        let second = connection(first.app, host: "two.test", address: first.address)
        var state = MonitorFeature.State()
        state.snapshot = .init(rows: [first, second])
        state.locations = [first.address: "US"]
        let original = state.snapshot.rows
        let destination = try #require(state.activityTree.nodes.values.first {
            $0.kind == .destination && $0.title == "one.test"
        })
        state.home.selection = destination.id
        #expect(state.homePresentation.selected.policy == .allow)
        state.snapshot.rules = [try .init(domain: "one.test")]
        let blocked = state.homePresentation
        #expect(blocked.selected.policy == .block)
        #expect(blocked.destinations.first?.blocked == 3)
        #expect(blocked.destinations.first?.focusedCount == 3)
        let app = try #require(state.activityTree.nodes.values.first { $0.kind == .application })
        #expect(app.policy == .mixed)
        #expect(state.activityTree.nodes[destination.id]?.policy == .block)
        state.snapshot.rules[0].enabled = false
        #expect(state.homePresentation.selected.policy == .allow)
        #expect(state.homePresentation.destinations.first?.blocked == 0)
        #expect(state.snapshot.rows == original)
    }

    @Test func home_policy_includes_blocklists_and_keeps_incoming_observation_allowed() throws {
        let outgoing = connection(
            "/Applications/Example.app/Contents/MacOS/Main",
            host: "one.test",
            address: "192.0.2.1"
        )
        var incoming = outgoing
        incoming.id = UUID()
        incoming.direction = .inbound
        var state = MonitorFeature.State()
        state.snapshot = .init(rows: [outgoing, incoming])
        state.snapshot.blocklistMatches = [
            outgoing.id.uuidString: UUID(),
            incoming.id.uuidString: UUID()
        ]
        #expect(state.homePresentation.selected.policy == .mixed)
        let leaves = state.activityTree.nodes.values.filter { $0.kind == .connection }
        #expect(leaves.first { $0.connection?.id == outgoing.id }?.policy == .block)
        #expect(leaves.first { $0.connection?.id == incoming.id }?.policy == .allow)
    }

    @Test func collapsed_presentation_materializes_only_disclosed_branches() throws {
        let rows = (0 ..< 2000).map { index in
            connection(
                "/Applications/Example.app/Contents/MacOS/Main",
                host: "peer-\(index).test",
                address: "192.0.2.1"
            )
        }
        var navigation = ActivityTree.Navigation()
        let collapsed = ActivityTree(rows: rows, expanded: navigation.expanded)
        #expect(collapsed.nodes.count == 2)
        let app = try #require(collapsed.roots.first)
        #expect(collapsed.nodes[app]?.hasChildren == true)
        navigation.expanded.insert(app)
        let disclosed = ActivityTree(rows: rows, expanded: navigation.expanded)
        #expect(disclosed.nodes.count == 2002)
        #expect(!disclosed.nodes.values.contains { $0.kind == .connection })
        let destination = try #require(disclosed.nodes[app]?.children.first)
        navigation.expanded.insert(destination)
        let inspected = ActivityTree(rows: rows, expanded: navigation.expanded)
        #expect(inspected.nodes.values.filter { $0.kind == .connection }.count == 1)
        #expect(inspected.nodes[app]?.count == 2000)
    }

    @Test func incoming_selection_is_searchable_and_does_not_create_an_outgoing_rule() async throws {
        let runtime = try Firewall.Runtime()
        let incoming = Firewall.Connection(
            app: "/server",
            host: nil,
            address: "192.0.2.1",
            port: "50000",
            transport: "TCP",
            blocked: false,
            direction: .inbound
        )
        let outgoing = Firewall.Connection(
            app: "/IncomingMail",
            host: "incoming.mail.test",
            address: "192.0.2.2",
            port: "993",
            transport: "TCP",
            blocked: false
        )
        var initial = MonitorFeature.State()
        initial.snapshot = .init(rows: [incoming, outgoing])
        initial.page = .activity
        var searchable = initial
        searchable.query = "incoming"
        #expect(searchable.matchingRows.map(\.id) == [incoming.id])
        searchable.query = "outgoing"
        #expect(searchable.matchingRows.map(\.id) == [outgoing.id])
        searchable.query = "inbound"
        #expect(searchable.matchingRows.map(\.id) == [incoming.id])
        searchable.query = "incoming.mail"
        #expect(searchable.matchingRows.map(\.id) == [outgoing.id])
        let store = TestStore(initialState: initial) {
            MonitorFeature(client: .init(runtime: runtime))
        }
        await store.send(.blockDestination) {
            $0.error = "Only outgoing connections use blocking rules. Incoming connections are observed."
        }
        #expect(runtime.snapshot().rules.isEmpty)
    }

    private func connection(
        _ app: String,
        host: String,
        address: String,
        count: Int = 1
    ) -> Firewall.Connection {
        .init(
            app: app,
            host: host,
            address: address,
            port: "443",
            transport: "TCP",
            blocked: false,
            count: count
        )
    }

    @Test func bundles_contain_helpers_and_system_services_have_selectable_executables() throws {
        let main = connection(
            "/Applications/Example.app/Contents/MacOS/Main",
            host: "one.test",
            address: "8.8.8.8"
        )
        let helper = connection(
            "/Applications/Example.app/Contents/Helpers/Helper.app/Contents/MacOS/Helper",
            host: "two.test",
            address: "1.1.1.1"
        )
        let daemon = connection(
            "/usr/sbin/mDNSResponder",
            host: "local.test",
            address: "192.168.1.1"
        )
        let tree = ActivityTree(rows: [main, helper, daemon])
        let app = try #require(tree.nodes.values.first { $0.kind == .application && $0.title == "Example" })
        #expect(app.connections == [main.id, helper.id])
        #expect(app.scope?.scope == .bundle)
        #expect(app.children.count == 2)
        let system = try #require(tree.nodes.values.first { $0.kind == .system })
        #expect(system.scope == nil)
        #expect(system.children.compactMap { tree.nodes[$0]?.title } == ["mDNSResponder"])
        var navigation = ActivityTree.Navigation()
        #expect(!tree.visible(navigation).contains { $0.node.kind == .service })
        navigation.expanded.insert(app.id)
        #expect(tree.visible(navigation).filter { $0.node.kind == .service }.count == 2)
        let refreshed = ActivityTree(rows: [daemon, helper, main])
        #expect(Set(refreshed.nodes.keys) == Set(tree.nodes.keys))
    }

    @Test func focusing_each_level_scopes_both_map_highlights_and_full_screen_rows() throws {
        let main = connection(
            "/Applications/Example.app/Contents/MacOS/Main",
            host: "one.test",
            address: "8.8.8.8"
        )
        let helper = connection(
            "/Applications/Example.app/Contents/Helpers/Helper",
            host: "two.test",
            address: "1.1.1.1"
        )
        let other = connection(
            "/Applications/Other.app/Contents/MacOS/Other",
            host: "three.test",
            address: "9.9.9.9"
        )
        var state = MonitorFeature.State()
        state.snapshot = Firewall.Snapshot(rows: [main, helper, other])
        state.locations = [main.address: "US", helper.address: "AU", other.address: "DE"]
        let app = try #require(state.activityTree.nodes.values.first { $0.title == "Example" })
        state.home.selection = app.id
        #expect(Set(state.focusedRows.map(\.id)) == [main.id, helper.id])
        #expect(Set(state.mapDestinations.filter(\.highlighted).map(\.code)) == ["US", "AU"])
        state.page = .activity
        #expect(Set(state.rows.map(\.id)) == [main.id, helper.id])
        let leaf = try #require(state.activityTree.nodes.values.first { $0.connection?.id == helper.id })
        state.home.selection = leaf.id
        #expect(state.rows.map(\.id) == [helper.id])
        #expect(state.mapDestinations.filter(\.highlighted).map(\.code) == ["AU"])
    }

    @Test func disclosure_and_connection_activation_preserve_the_selected_entity() async throws {
        let runtime = try Firewall.Runtime()
        let row = connection(
            "/Applications/Example.app/Contents/MacOS/Main",
            host: "one.test",
            address: "8.8.8.8"
        )
        var initial = MonitorFeature.State()
        initial.snapshot = Firewall.Snapshot(rows: [row])
        let app = try #require(initial.activityTree.nodes.values.first { $0.kind == .application })
        let leaf = try #require(initial.activityTree.nodes.values.first { $0.connection?.id == row.id })
        let store = TestStore(initialState: initial) {
            MonitorFeature(client: .init(runtime: runtime))
        }
        await store.send(.toggleNode(app.id)) {
            $0.home.selection = app.id
            $0.home.expanded.insert(app.id)
        }
        await store.send(.activateNode(leaf.id)) {
            $0.home.selection = leaf.id
            $0.detail = row
        }
        await store.send(.closeDetail) { $0.detail = nil }
        #expect(store.state.home.selection == leaf.id)
        #expect(store.state.home.expanded.contains(app.id))
        let event = Event(nark.ux.monitor.home.tree.row[app.id].disclosure.event.select)
        guard case .toggleNode(let id) = MonitorFeature.Session.action(for: event) else {
            Issue.record("Disclosure lost its row context")
            return
        }
        #expect(id == app.id)
    }
}
