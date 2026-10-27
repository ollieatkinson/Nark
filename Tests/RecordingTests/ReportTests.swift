import Firewall
import Foundation
import Recording
import Testing

@Suite struct ReportTests {

    @Test func reports_keep_opposite_directions_and_receiving_ports_distinct() throws {
        let runtime = try Firewall.Runtime()
        let app = try Firewall.Application(path: "/app", scope: .executable)
        let initial = try runtime.recording(.start(app))
        for (direction, port) in [
            (Firewall.Direction.outbound, "50000"),
            (.inbound, "8080"),
            (.inbound, "9090")
        ] {
            _ = runtime.evaluate(.init(
                app: app.path,
                host: "peer.test",
                address: "192.0.2.1",
                port: "443",
                transport: "TCP",
                blocked: false,
                direction: direction,
                localAddress: "192.0.2.2",
                localPort: port
            ))
        }
        var summary = RecordingSummary(initial)
        try summary.append(runtime.recording(.stop(.init(id: initial.id, after: 0))))
        let report = summary.report
        #expect(report.schemaVersion == 2)
        #expect(report.destinations.count == 3)
        #expect(report.destinations.filter { $0.direction == .inbound }.count == 2)
        #expect(report.destinations.first { $0.direction == .outbound }?.localPort == nil)
        #expect(report.markdown().contains("| Incoming | peer.test |"))
        #expect(report.markdown().contains("| Outgoing | peer.test |"))
        #expect(report.markdown().contains("8080"))
        let json = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        let destinations = try #require(json["destinations"] as? [[String: Any]])
        #expect(Set(destinations.compactMap { $0["direction"] as? String }) == [
            "inbound",
            "outbound"
        ])
    }

    @Test func report_and_journal_include_only_new_scoped_flows_and_are_owner_only() throws {
        let runtime = try Firewall.Runtime()
        let app = try Firewall.Application(path: "/usr/bin/curl", scope: .executable)
        let row = Firewall.Connection(
            app: app.path,
            host: "example.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        runtime.record(row)
        let initial = try runtime.recording(.start(app))
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RecordingJournal(directory: directory, initial: initial)
        runtime.record(row)
        runtime.record(row)
        _ = runtime.handle(.add(try Firewall.Rule(domain: "example.test")))
        _ = runtime.evaluate(row)
        let batch = try runtime.recording(.stop(.init(id: initial.id, after: 0)))
        try journal.append(batch)
        try journal.finish()
        #expect(journal.report.status == .complete)
        #expect(journal.report.observedConnections == 3)
        #expect(journal.report.allowed == 2)
        #expect(journal.report.blocked == 1)
        #expect(journal.report.destinations.count == 1)
        let raw = try String(
            contentsOf: directory.appendingPathComponent("connections.jsonl"),
            encoding: .utf8
        )
        let lines = try raw.split(separator: "\n")
            .map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        #expect(lines.map { $0["kind"] as? String } == [
            "started",
            "connection",
            "connection",
            "connection",
            "ended"
        ])
        #expect(try String(
            contentsOf: directory.appendingPathComponent("report.md"),
            encoding: .utf8
        ).contains("3 observed connections"))
        let json = try JSONSerialization
            .jsonObject(with: Data(contentsOf: directory
                    .appendingPathComponent("report.json"))) as! [String: Any]
        #expect(json["status"] as? String == "complete")
        for name in ["connections.jsonl", "report.md", "report.json"] {
            let attributes = try FileManager.default
                .attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        #expect(throws: (any Error).self) { try RecordingJournal(
            directory: directory,
            initial: initial
        ) }
    }

    @Test func stopped_sessions_are_complete_only_after_all_pages_are_drained() throws {
        let runtime = try Firewall.Runtime()
        let app = try Firewall.Application(path: "/app", scope: .executable)
        let initial = try runtime.recording(.start(app))
        for _ in 0 ..< 600 {
            runtime.record(.init(
                app: app.path,
                host: "example.test",
                address: "192.0.2.1",
                port: "443",
                transport: "TCP",
                blocked: false
            ))
        }
        var summary = RecordingSummary(initial)
        var batch = try runtime.recording(.stop(.init(id: initial.id, after: 0)))
        #expect(batch.hasMore)
        try summary.append(batch)
        #expect(summary.report.status == .recording)
        while batch.hasMore {
            batch = try runtime.recording(.read(.init(id: initial.id, after: summary.cursor)))
            try summary.append(batch)
        }
        #expect(summary.report.status == .complete)
        #expect(summary.report.observedConnections == 600)
    }

    @Test func interrupted_recording_keeps_a_readable_partial_report() throws {
        let runtime = try Firewall.Runtime()
        let initial = try runtime.recording(.start(try Firewall.Application(
            path: "/app",
            scope: .executable
        )))
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RecordingJournal(directory: directory, initial: initial)
        runtime.record(.init(
            app: "/app",
            host: "<untrusted>|site.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        ))
        try journal.append(runtime.recording(.read(.init(id: initial.id, after: 0))))
        try journal.finish(error: "filter restarted")
        #expect(journal.report.status == .incomplete)
        #expect(journal.report.observedConnections == 1)
        #expect(journal.report.markdown().contains("\\<untrusted\\>\\|site.test"))
        let json = try JSONSerialization
            .jsonObject(with: Data(contentsOf: directory
                    .appendingPathComponent("report.json"))) as! [String: Any]
        #expect(json["error"] as? String == "filter restarted")
    }

    @Test func lost_events_and_provider_failures_are_never_labelled_complete() throws {
        let runtime = try Firewall.Runtime()
        let app = try Firewall.Application(path: "/app", scope: .executable)
        let initial = try runtime.recording(.start(app))
        for _ in 0 ..< 4100 {
            runtime.record(.init(
                app: app.path,
                host: nil,
                address: "192.0.2.1",
                port: "443",
                transport: "TCP",
                blocked: false
            ))
        }
        var summary = RecordingSummary(initial)
        var batch = try runtime.recording(.stop(.init(id: initial.id, after: 0)))
        while true {
            try summary.append(batch)
            if !batch.hasMore {
                break
            }
            batch = try runtime.recording(.read(.init(id: initial.id, after: summary.cursor)))
        }
        #expect(summary.report.missingConnections == 4)
        #expect(summary.report.status == .incomplete)
        #expect(summary.report.observedConnections == 4096)
        summary.fail("filter restarted")
        #expect(summary.report.error == "filter restarted")
        #expect(summary.report.markdown().contains("Incomplete"))
    }
}
