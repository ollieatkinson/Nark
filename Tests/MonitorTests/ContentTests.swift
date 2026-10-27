import Firewall
import Foundation
@testable import Monitor
import Testing

@Suite struct ContentTests {

    @Test func activity_refresh_matches_a_full_rebuild_with_filtering_and_nested_services() throws {
        var snapshot = Firewall.Snapshot(rows: (0 ..< 80).map { index in
            Firewall.Connection(
                app: index.isMultiple(of: 2)
                    ? "/Applications/Example.app/Contents/MacOS/Main"
                    : "/Applications/Example.app/Contents/Helpers/Worker",
                host: "host-\(index).test",
                address: "192.0.2.1",
                port: "443",
                transport: "TCP",
                blocked: false,
                count: 1
            )
        })
        var activity = MonitorFeature.Activity()
        let start = Date(timeIntervalSince1970: 100)
        activity.record(snapshot, at: start)
        snapshot.rows[0].count += 12
        activity.record(snapshot, at: start.addingTimeInterval(1))
        for query in ["", "host-0"] {
            for application in [nil, try Firewall.Application(path: "/Applications/Example.app", scope: .bundle)] {
                let previous = MonitorFeature.Content(snapshot: snapshot, query: query, application: application)
                let refreshed = MonitorFeature.Content(previous: previous, activity: activity)
                let rebuilt = MonitorFeature.Content(
                    snapshot: snapshot,
                    query: query,
                    application: application,
                    activity: activity
                )
                #expect(refreshed == rebuilt)
                #expect(refreshed.home.maximumRecent == rebuilt.home.maximumRecent)
            }
        }
    }

    @Test func navigation_reuses_the_traffic_index_and_disclosure_only_changes_the_outline() {
        var state = MonitorFeature.State()
        state.snapshot = .init(rows: (0 ..< 2000).map { index in
            Firewall.Connection(
                app: "/Applications/App\(index % 80).app/Contents/MacOS/App",
                host: "host-\(index).test",
                address: "192.0.2.1",
                port: "443",
                transport: "TCP",
                blocked: false
            )
        })
        let content = state.content
        let outline = state.outline
        for id in content.home.tree.roots {
            state.home.selection = id
            _ = state.homePresentation
            state.page = .activity
            _ = state.rows
            _ = state.trafficSamples
            state.page = .home
            #expect(state.content === content)
            #expect(state.outline == outline)
        }
        state.home.expanded.insert(content.home.tree.roots[0])
        #expect(state.content === content)
        #expect(state.outline.count > outline.count)
    }

    @Test func policy_query_and_country_changes_refresh_the_index_without_losing_focus() throws {
        let row = Firewall.Connection(
            app: "/Applications/Example.app/Contents/MacOS/App",
            host: "one.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        var state = MonitorFeature.State()
        state.snapshot = .init(rows: [row])
        let id = try #require(state.content.home.tree.roots.first)
        state.home.selection = id
        let initial = state.content
        state.locations = [row.address: "GB"]
        #expect(state.content !== initial)
        #expect(state.homePresentation.destinations.first?.code == "GB")
        state.snapshot.rules = [try .init(domain: "one.test")]
        #expect(state.homePresentation.selected.policy == .block)
        #expect(state.homePresentation.destinations.first?.blocked == 1)
        state.page = .activity
        state.query = "missing"
        #expect(state.rows.isEmpty)
        #expect(state.focusedNode?.id == id)
        state.query = ""
        #expect(state.rows.map(\.id) == [row.id])
    }
}
