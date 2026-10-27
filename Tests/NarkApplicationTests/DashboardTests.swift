import Control
import Firewall
import Foundation
import IssueReportingTestSupport
import Monitor
@testable import NarkApplication
import NarkUI
import SwiftTUI
import SwiftTUICLI
import SwiftTUIRuntime
import Testing
import TestSupport
import Vocabulary

@Suite @MainActor struct DashboardTests {

    @Test(arguments: [(80, 24), (140, 42)])
    func home_labels_a_newly_blocked_site_before_another_flow_arrives(size: (Int, Int)) throws {
        let runtime = try Firewall.Runtime()
        let row = Firewall.Connection(
            app: "/Applications/Example.app/Contents/MacOS/Main",
            host: "one.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        let session = MonitorFeature.Session(client: .init(runtime: runtime))
        session.store.send(.received(.init(rows: [row])))
        let tree = session.store.activityTree
        let app = try #require(tree.nodes.values.first { $0.kind == .application })
        let site = try #require(tree.nodes.values.first { $0.kind == .destination })
        session.store.send(.toggleNode(app.id))
        session.store.send(.selectNode(site.id))
        var snapshot = session.store.snapshot
        snapshot.rules = [try .init(domain: "one.test")]
        session.store.send(.received(snapshot))
        let output = RenderOnce.render(
            MonitorDashboard(session: session).terminalViewport(width: size.0, height: size.1),
            width: size.0,
            environment: ["NO_COLOR": "1", "TERM": "xterm-256color", "LANG": "en_US.UTF-8"],
            isStdoutTTY: false
        )
        #expect(output.contains("Policy: BLOCK"))
        #expect(output.contains("× one.test"))
        #expect(session.store.snapshot.rows.first?.blocked == false)
    }

    @Test(arguments: [(70, 20), (80, 24), (140, 42)])
    func direction_icons_distinguish_tree_groups_table_rows_and_incoming_details(size: (
        Int,
        Int
    )) throws {
        let runtime = try Firewall.Runtime()
        let outgoing = Firewall.Connection(
            app: "/Applications/Example.app/Contents/MacOS/Main",
            host: "peer.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        var incoming = outgoing
        incoming.id = UUID()
        incoming.direction = .inbound
        incoming.localAddress = "192.0.2.2"
        incoming.localPort = "8080"
        let session = MonitorFeature.Session(client: .init(runtime: runtime))
        session.store.send(.received(.init(rows: [outgoing, incoming])))
        let app = try #require(session.store.activityTree.nodes.values.first { $0.kind == .application })
        session.store.send(.toggleNode(app.id))
        func render(height: Int? = nil) -> String {
            let h = height ?? size.1
            return RenderOnce.render(
                MonitorDashboard(session: session).terminalViewport(width: size.0, height: h),
                width: size.0,
                environment: ["NO_COLOR": "1", "TERM": "xterm-256color", "LANG": "en_US.UTF-8"],
                isStdoutTTY: false
            )
        }
        #expect(render().contains("↔ peer.test"))
        session.store.send(.show(.activity))
        let list = render()
        #expect(list.contains("DIR"))
        #expect(list.contains("↗"))
        #expect(list.contains("↙"))
        let lines = list.components(separatedBy: "\n")
        #expect(lines.count <= size.1 + 1)
        #expect(lines.allSatisfy { $0.count <= size.0 })
        session.store.send(.openConnection(incoming.id))
        let detail = render(height: 42)
        #expect(detail.contains("Incoming · peer.test"))
        #expect(detail.contains("192.0.2.2:8080"))
        #expect(detail.contains("ALLOW · observation only"))
        #expect(!detail.contains("[b block site]"))
        #expect(!detail.contains("[x block app+site]"))
    }

    @Test(arguments: [(70, 20), (80, 24), (120, 36)])
    func layout_shows_real_policy_and_observed_verdict_at_terminal_sizes(size: (Int, Int)) throws {
        let runtime = try Firewall.Runtime()
        let row = Firewall.Connection(
            app: "/usr/bin/curl",
            host: "example.com",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        runtime.record(row)
        _ = runtime.handle(.add(try Firewall.Rule(domain: "example.com")))
        let session = MonitorFeature.Session(client: .init(runtime: runtime))
        session.store.send(.received(runtime.snapshot()))
        session.store.send(.show(.activity))
        let output = RenderOnce.render(
            MonitorDashboard(session: session).terminalViewport(width: size.0, height: size.1),
            width: size.0,
            environment: [
                "NO_COLOR": "1",
                "TERM": "xterm-256color",
                "LANG": "en_US.UTF-8"
            ],
            isStdoutTTY: false
        )
        #expect(output.contains("NARK"))
        #expect(output.contains("connections"))
        #expect(output.contains("REMOTE"))
        #expect(output.contains("[all] app service remote local port type dir policy"))
        #expect(output.contains("example.com"))
        #expect(output.contains("BLOCK"))
        #expect(output.contains("last observed allowed"))
        #expect(output.contains("q quit"))
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count <= size.1 + 1)
        #expect(lines.allSatisfy { $0.count <= size.0 })
        try output.write(
            toFile: "/tmp/nark-preview-\(size.0)x\(size.1).txt",
            atomically: true,
            encoding: .utf8
        )
    }

    @Test func semantic_list_realizes_only_the_visible_band_of_large_activity() {
        struct Item {

            let id: String
        }
        final class Counter {

            var rows = 0
        }
        let counter = Counter()
        let items = (0 ..< 2000).map { Item(id: String($0)) }
        let events = Events()
        let list = UI.List(
            items,
            row: nark.ux.monitor.connections.row,
            id: \.id,
            selection: "0",
            height: 12
        ) { _, item in
            counter.rows += 1
            return Text("row \(item.id)")
        }
        .events(events) { Issue.record($0) }
        .frame(width: 80, height: 12)
        let output = RenderOnce.render(
            list,
            width: 80,
            environment: [
                "NO_COLOR": "1",
                "TERM": "xterm-256color",
                "LANG": "en_US.UTF-8"
            ],
            isStdoutTTY: false
        )
        #expect(output.contains("row 0"))
        #expect(counter.rows < 100)
    }

    @Test(arguments: [(70, 20), (80, 24), (140, 42), (200, 60)])
    func full_dashboard_bounds_large_lists_to_the_terminal_viewport(size: (Int, Int)) throws {
        let runtime = try Firewall.Runtime()
        let session = MonitorFeature.Session(client: .init(runtime: runtime))
        let rows = (0 ..< 2000).map { index in
            Firewall.Connection(
                app: "/Applications/App\(index % 80).app/Contents/MacOS/App",
                host: "host-\(index).test",
                address: "192.0.2.1",
                port: "443",
                transport: "TCP",
                blocked: false
            )
        }
        session.store.send(.received(Firewall.Snapshot(rows: rows)))
        let frame = DefaultRenderer().render(
            MonitorDashboard(session: session).terminalViewport(width: size.0, height: size.1),
            proposal: .init(width: size.0, height: size.1)
        )
        let collectionIssues = frame.diagnostics.runtime.issues.filter { $0.code.hasPrefix("collection.") }
        #expect(collectionIssues.isEmpty, "\(collectionIssues)")
        #expect(frame.diagnostics.work.layoutDependentRealizations == 0)
        #expect(frame.diagnostics.work.layoutDependentMainActorFallbacks == 0)
    }

    @Test func reusable_control_preserves_feature_path_and_context_on_shared_bus() async throws {
        let events = Events()
        let stream = events.stream
        let control = UI.Control(nark.ux.monitor.rules.add["example.com"])
        try events.send(control.select)
        events.finish()
        var iterator = stream.makeAsyncIterator()
        let event = try #require(await iterator.next())
        #expect(event.matches(nark.ux.monitor.rules.add.event.select))
        #expect(try event[nark.ux.monitor.rules.add, as: String.self] == "example.com")
        #expect(event.matches((any I_nark_ui_type_action).self))
    }

    @Test func untrusted_terminal_content_cannot_embed_escape_sequences() {
        #expect("hello\u{1b}[2J\nworld\t".formatted(.terminalText) == "hello[2Jworld")
    }
}

extension DashboardTests {

    @Test(arguments: [(70, 20), (80, 24), (120, 36)])
    func rules_details_and_map_have_independent_bounded_layouts(size: (Int, Int)) throws {
        let runtime = try Firewall.Runtime()
        let row = Firewall.Connection(
            app: "/Applications/Example.app/Contents/MacOS/Example",
            host: "example.com",
            address: "8.8.8.8",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        runtime.record(row)
        _ = runtime.handle(.add(try Firewall.Rule(domain: "example.com")))
        let session = MonitorFeature.Session(client: .init(runtime: runtime))
        session.store.send(.received(runtime.snapshot()))
        session.store.send(.located(["8.8.8.8": "US"]))
        func render(_ name: String) throws -> String {
            let output = RenderOnce.render(
                MonitorDashboard(session: session).terminalViewport(width: size.0, height: size.1),
                width: size.0,
                environment: ["NO_COLOR": "1", "TERM": "xterm-256color", "LANG": "en_US.UTF-8"],
                isStdoutTTY: false
            )
            try output.write(
                toFile: "/tmp/nark-preview-\(name)-\(size.0)x\(size.1).txt",
                atomically: true,
                encoding: .utf8
            )
            let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines.count <= size.1 + 1)
            #expect(lines.allSatisfy { $0.count <= size.0 })
            #expect(output.contains("q quit"))
            return output
        }
        session.store.send(.show(.rules))
        let rules = try render("rules")
        #expect(!rules.contains("│applications"))
        #expect(!rules.contains("traffic ·"))
        #expect(rules.contains("APPLICATION"))
        #expect(rules.contains("example.com"))
        session.store.send(.show(.activity))
        session.store.send(.openConnection(row.id))
        let detail = try render("detail")
        #expect(detail.contains("Executable"))
        #expect(detail.contains("Observed flows"))
        #expect(detail.contains("United States"))
        session.store.send(.show(.map))
        let map = try render("map")
        #expect(map.contains("applications"))
        #expect(!map.contains("This Mac"))
        #expect(map.contains("DB-IP"))
    }
}

extension DashboardTests {

    @Test(arguments: [(80, 24), (140, 42)])
    func collection_columns_align_headings_and_values_despite_varying_counts(size: (
        Int,
        Int
    )) throws {
        let runtime = try Firewall.Runtime()
        let session = MonitorFeature.Session(client: .init(runtime: runtime))
        let alpha = Firewall.Connection(
            app: "/AlphaTool",
            host: "alpha.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false,
            count: 10
        )
        let beta = Firewall.Connection(
            app: "/BetaTool",
            host: "beta.test",
            address: "192.0.2.2",
            port: "443",
            transport: "TCP",
            blocked: false,
            count: 9000
        )
        let start = Date(timeIntervalSince1970: 100)
        var snapshot = Firewall.Snapshot(rows: [alpha, beta], traffic: Firewall.Traffic())
        session.store.send(.received(snapshot))
        session.store.send(.tick(start))
        snapshot.rows[0].count += 3
        snapshot.rows[1].count += 9
        session.store.send(.received(snapshot))
        session.store.send(.tick(start.addingTimeInterval(1)))
        let output = RenderOnce.render(
            MonitorDashboard(session: session).terminalViewport(width: size.0, height: size.1),
            width: size.0,
            environment: ["NO_COLOR": "1", "TERM": "xterm-256color", "LANG": "en_US.UTF-8"],
            isStdoutTTY: false
        )
        try output.write(
            toFile: "/tmp/nark-alignment-\(size.0)x\(size.1).txt",
            atomically: true,
            encoding: .utf8
        )
        let lines = output.components(separatedBy: "\n")
        func pane(_ line: String, index: Int) -> String {
            line.components(separatedBy: "│")[index]
        }
        func startOf(_ word: String, in line: String) throws -> Int {
            let range = try #require(line.range(of: word))
            return line.distance(from: line.startIndex, to: range.lowerBound)
        }
        func endOf(
            _ word: String,
            in line: String
        ) throws -> Int {
            try startOf(word, in: line) + word.count
        }
        let appHeader = pane(try #require(lines.first { $0.contains("RECENT") }), index: 1)
        let a = pane(try #require(lines.first { $0.contains("AlphaTool") }), index: 1)
        let b = pane(try #require(lines.first { $0.contains("BetaTool") }), index: 1)
        #expect(try startOf("APPLICATION", in: appHeader) == startOf("AlphaTool", in: a))
        #expect(try endOf("FLOWS", in: appHeader) == endOf("13", in: a))
        #expect(try endOf("FLOWS", in: appHeader) == endOf("9009", in: b))
        #expect(try startOf("RECENT", in: appHeader) == startOf("━━────", in: a))
        #expect(try startOf("RECENT", in: appHeader) == startOf("━━━━━━", in: b))
        session.store.send(.show(.activity))
        let table = RenderOnce.render(
            MonitorDashboard(session: session).terminalViewport(width: size.0, height: size.1),
            width: size.0,
            environment: ["NO_COLOR": "1", "TERM": "xterm-256color", "LANG": "en_US.UTF-8"],
            isStdoutTTY: false
        )
        let tableLines = table.components(separatedBy: "\n")
        let destinationHeader = pane(
            try #require(tableLines.first { $0.contains("REMOTE") }),
            index: 1
        )
        let destination = pane(
            try #require(tableLines.first { $0.contains("alpha.test") }),
            index: 1
        )
        #expect(try startOf("REMOTE", in: destinationHeader) == startOf(
            "alpha.test",
            in: destination
        ))
        #expect(try endOf("POLICY", in: destinationHeader) == endOf("ALLOW", in: destination))
        #expect(!table.contains("RECENT"))
    }
}

extension DashboardTests {

    @Test(arguments: [(70, 20), (80, 24), (140, 42)])
    func home_discloses_helpers_and_connections_and_list_uses_the_selected_scope(size: (
        Int,
        Int
    )) throws {
        let runtime = try Firewall.Runtime()
        let main = Firewall.Connection(
            app: "/Applications/Example.app/Contents/MacOS/Main",
            host: "one.test",
            address: "8.8.8.8",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        let helper = Firewall.Connection(
            app: "/Applications/Example.app/Contents/Helpers/Helper",
            host: "two.test",
            address: "1.1.1.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        let other = Firewall.Connection(
            app: "/Applications/Other.app/Contents/MacOS/Other",
            host: "other.test",
            address: "9.9.9.9",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        let session = MonitorFeature.Session(client: .init(runtime: runtime))
        session.store.send(.received(.init(rows: [main, helper, other])))
        session.store.send(
            .located(
                [
                    main.address: "US",
                    helper.address: "AU",
                    other.address: "DE"
                ]
            )
        )
        func render() -> String {
            RenderOnce.render(
                MonitorDashboard(session: session).terminalViewport(width: size.0, height: size.1),
                width: size.0,
                environment: ["NO_COLOR": "1", "TERM": "xterm-256color", "LANG": "en_US.UTF-8"],
                isStdoutTTY: false
            )
        }
        #expect(session.store.page == .home)
        let home = render()
        let trafficHeading = try #require(home.range(of: "traffic ·"))
        let applicationsHeading = try #require(home.range(of: "applications"))
        #expect(trafficHeading.lowerBound < applicationsHeading.lowerBound)
        #expect(home.contains("↑ 0 B/s"))
        #expect(home.contains("↓ 0 B/s"))
        #expect(home.contains("▸ Example"))
        #expect(!home.contains("Helper"))
        #expect(!home.contains("This Mac"))
        let app = try #require(session.store.activityTree.nodes.values.first {
            $0.kind == .application && $0.title == "Example"
        })
        let service = try #require(session.store.activityTree.nodes.values.first {
            $0.kind == .service && $0.title == "Helper"
        })
        session.store.send(.toggleNode(app.id))
        #expect(render().contains("▸ Helper"))
        session.store.send(.toggleNode(service.id))
        #expect(render().contains("two.test"))
        session.store.send(.toggleList)
        let list = render()
        #expect(list.contains("two.test"))
        #expect(!list.contains("other.test"))
        #expect(!list.contains("RECENT"))
        session.store.send(.toggleList)
        #expect(session.store.home.selection == service.id)
        #expect(render().contains("two.test"))
    }

    @Test func blocklist_browser_windows_large_sources_and_keeps_source_identity() throws {
        let runtime = try Firewall.Runtime()
        let preset = Firewall.Blocklist.presets[0].summary
        let text = (0 ..< 20000).map { String(format: "ad-%05d.test", $0) }.joined(separator: "\n")
        #expect(runtime.handle(
            .blocklist(
                .replace(
                    .init(
                        id: preset.id,
                        name: preset.name,
                        source: preset.source,
                        text: text
                    )
                )
            )
        )
        .error == nil)
        let list = try #require(runtime.handle(.blocklist(.read(preset.id))).blocklist)
        let session = MonitorFeature.Session(client: .init(runtime: runtime))
        session.store.send(.show(.rules))
        session.store.send(.blocklists(.loaded(list)))
        let frame = DefaultRenderer().render(
            MonitorDashboard(session: session).terminalViewport(width: 100, height: 30),
            proposal: .init(width: 100, height: 30)
        )
        #expect(frame.diagnostics
            .runtime
            .issues
            .filter { $0.code.hasPrefix("collection.") }
            .isEmpty)
        #expect(session.store.blocklists.detail?.summary.source == preset.source)
        session.store.send(.search("ad-19999"))
        #expect(session.store.blocklists.domains == ["ad-19999.test"])
    }
}

extension DashboardTests {

    @Test(arguments: [(70, 20), (80, 24), (140, 42)])
    func community_picker_exposes_categories_descriptions_and_url_import(size: (Int, Int)) throws {
        let runtime = try Firewall.Runtime()
        let session = MonitorFeature.Session(client: .init(runtime: runtime))
        session.store.send(.blocklists(.showCommunity))
        let output = RenderOnce.render(
            MonitorDashboard(session: session).terminalViewport(width: size.0, height: size.1),
            width: size.0,
            environment: ["NO_COLOR": "1", "TERM": "xterm-256color", "LANG": "en_US.UTF-8"],
            isStdoutTTY: false
        )
        #expect(output.contains("community blocklists"))
        #expect(output.contains("Category: All"))
        #expect(output.contains("i paste URL"))
        #expect(output.contains("Added lists start off"))
        #expect(output.components(separatedBy: "\n").count <= size.1 + 1)
        try output.write(
            toFile: "/tmp/nark-community-\(size.0)x\(size.1).txt",
            atomically: true,
            encoding: .utf8
        )
    }
}

private extension View {

    func terminalViewport(width: Int, height: Int) -> some View {
        environment(\.terminalSize, CellSize(width: width, height: height))
            .frame(
                width: width,
                height: height
            )
    }
}

extension DashboardTests {

    @Test func collection_overflow_does_not_move_the_first_row() {
        func firstRow(count: Int) -> Int? {
            let list = UI.List(
                Array(0 ..< count),
                row: nark.ux.monitor.connections.row,
                id: \.self,
                selection: 0,
                height: 10
            ) { _, item in
                Text("item \(item)")
            }
            .frame(width: 40, height: 10)
            let output = RenderOnce.render(
                list,
                width: 40,
                environment: ["NO_COLOR": "1", "TERM": "xterm-256color"],
                isStdoutTTY: false
            )
            return output.components(separatedBy: "\n").firstIndex { $0.contains("item 0") }
        }
        #expect(firstRow(count: 5) != nil)
        #expect(firstRow(count: 5) == firstRow(count: 50))
    }
}
