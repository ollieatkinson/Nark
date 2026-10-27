@testable import Firewall
import Foundation
import Testing

@Suite struct FirewallTests {

    @Test func ip_rules_match_equivalent_ipv6_and_never_domain_suffixes() throws {
        let rule = try Firewall.Rule(domain: "2001:0db8:0000:0000:0000:0000:0000:0001")
        #expect(rule.domain == "2001:db8::1")
        #expect(rule.matches(app: "/test", host: nil, address: "2001:db8::1"))
        #expect(!Firewall.Hostname.matches("cdn.192.0.2.1", domain: "192.0.2.1"))
    }

    @Test func rules_match_app_and_domain_on_label_boundaries() throws {
        let rule = try Firewall.Rule(app: "/usr/bin/curl", domain: "Example.COM.")
        #expect(rule.matches(app: "/usr/bin/curl", host: "api.example.com", address: "192.0.2.1"))
        #expect(!rule.matches(app: "/usr/bin/other", host: "example.com", address: "192.0.2.1"))
        #expect(!rule.matches(app: "/usr/bin/curl", host: "notexample.com", address: "192.0.2.1"))
        #expect(!rule.matches(app: "/usr/bin/curl", host: "example.com.evil.test", address: "192.0.2.1"))
        let ip = try Firewall.Rule(domain: "192.0.2.1")
        #expect(ip.matches(app: "anything", host: nil, address: "192.0.2.1"))
        #expect(throws: (any Error).self) { try Firewall.Rule(domain: "https://example.com/path") }
        #expect(throws: (any Error).self) { try Firewall.Rule() }
        #expect(throws: (any Error).self) { try Firewall.Rule(app: "curl") }
    }

    @Test func policy_persists_and_toggle_changes_verdict() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = try Firewall.Runtime(directory: directory)
        let rule = try Firewall.Rule(domain: "example.com")
        #expect(runtime.handle(.add(rule)).error == nil)
        #expect(runtime.isBlocked(app: "/usr/bin/curl", host: "sub.example.com", address: "192.0.2.1"))
        let restarted = try Firewall.Runtime(directory: directory)
        #expect(restarted.snapshot().rules == [rule])
        #expect(restarted.handle(.toggle(rule.id)).error == nil)
        #expect(!restarted.isBlocked(app: "/usr/bin/curl", host: "example.com", address: "192.0.2.1"))
        #expect(restarted.handle(.remove(rule.id)).snapshot?.rules.isEmpty == true)
    }

    @Test func imports_are_atomic_and_accept_hosts_files() throws {
        let runtime = try Firewall.Runtime()
        let result = runtime.handle(
            .importDomains(
                "# hosts\n0.0.0.0 ADS.EXAMPLE.COM tracker.example.com # comment\nexample.org\n127.0.0.1 localhost\n"
            )
        )
        #expect(result.error == nil)
        #expect(
            result.snapshot?.rules.compactMap(\.domain) == [
                "ads.example.com",
                "example.org",
                "tracker.example.com",
            ]
        )
        #expect(runtime.handle(.importDomains("valid.test\n||adblock.test^$third-party\n")).error != nil)
        #expect(runtime.snapshot().rules.count == 3)
    }

    @Test func activity_aggregates_and_remains_bounded_and_clearable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = try Firewall.Runtime(directory: directory)
        let row = Firewall.Connection(
            app: "/usr/bin/curl",
            host: "example.com",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        runtime.record(row)
        runtime.record(row)
        #expect(runtime.snapshot().rows.first?.count == 2)
        for index in 0 ..< 2010 {
            runtime.record(
                Firewall.Connection(
                    app: "/test",
                    host: "\(index).example.com",
                    address: "192.0.2.2",
                    port: "443",
                    transport: "TCP",
                    blocked: true
                )
            )
        }
        #expect(runtime.snapshot().rows.count == 2000)
        #expect(runtime.snapshot().totalBlocked == 2010)
        try runtime.checkpoint()
        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("history.json").path
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try Firewall.Runtime(directory: directory, onHistoryFailure: { Issue.record($0) })
            .snapshot()
            .rows
            .count == 2000)
        #expect(runtime.handle(.clearHistory).snapshot?.rows.isEmpty == true)
        #expect(try Firewall.Runtime(directory: directory).snapshot().rows.isEmpty == true)
    }

    @Test func checkpoint_replaces_legacy_protected_history_with_readable_state() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        try JSONEncoder().encode(Firewall.Snapshot()).write(
            to: url,
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
        let runtime = try Firewall.Runtime(directory: directory)
        let row = Firewall.Connection(
            app: "/test",
            host: "persist.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
        runtime.record(row)
        try runtime.checkpoint()
        let restored = try Firewall.Runtime(
            directory: directory,
            onHistoryFailure: { Issue.record($0) }
        )
        #expect(restored.snapshot().rows.contains { $0.id == row.id })
    }

    @Test func corrupted_history_reports_failure_without_losing_policy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try Firewall.Runtime(directory: directory)
        let rule = try Firewall.Rule(domain: "example.com")
        #expect(original.handle(.add(rule)).error == nil)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("history.json"))
        var reported = false
        let restored = try Firewall.Runtime(
            directory: directory,
            onHistoryFailure: { _ in reported = true }
        )
        #expect(reported)
        #expect(restored.snapshot().rules == [rule])
        #expect(restored.snapshot().rows.isEmpty)
    }

    @Test func corrupted_policy_prevents_silent_unfiltered_startup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("broken".utf8).write(to: directory.appendingPathComponent("rules.json"))
        #expect(throws: (any Error).self) { try Firewall.Runtime(directory: directory) }
    }

    @Test func concurrent_recording_does_not_lose_counts() async throws {
        let runtime = try Firewall.Runtime()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    runtime.record(
                        Firewall.Connection(
                            app: "/test",
                            host: "example.com",
                            address: "192.0.2.1",
                            port: "443",
                            transport: "TCP",
                            blocked: false
                        )
                    )
                }
            }
        }
        #expect(runtime.snapshot().totalAllowed == 100)
        #expect(runtime.snapshot().rows.first?.count == 100)
    }
}

@Test func bundle_rules_reuse_application_scope_without_matching_sibling_bundles() throws {
    let rule = try Firewall.Rule(app: "/Applications/Example.app", applicationScope: .bundle)
    #expect(rule.matches(
        app: "/Applications/Example.app/Contents/MacOS/Main",
        host: nil,
        address: "8.8.8.8"
    ))
    #expect(rule.matches(
        app: "/Applications/Example.app/Contents/Helpers/Helper",
        host: nil,
        address: "8.8.8.8"
    ))
    #expect(!rule.matches(
        app: "/Applications/Example.app.copy/Contents/MacOS/Main",
        host: nil,
        address: "8.8.8.8"
    ))
    let decoded = try JSONDecoder().decode(Firewall.Rule.self, from: JSONEncoder().encode(rule)).validated()
    #expect(decoded.applicationScope == .bundle)
    let legacy = try Firewall.Rule(app: "/Applications/Example.app/Contents/MacOS/Main")
    #expect(!legacy.matches(
        app: "/Applications/Example.app/Contents/Helpers/Helper",
        host: nil,
        address: "8.8.8.8"
    ))
}
