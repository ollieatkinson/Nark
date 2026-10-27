@testable import Firewall
import Foundation
import Testing

@Suite struct BlocklistTests {

    @Test func lists_toggle_independently_match_subdomains_and_preserve_manual_rules() throws {
        let runtime = try Firewall.Runtime()
        let manual = try Firewall.Rule(domain: "manual.test")
        _ = runtime.handle(.add(manual))
        let preset = Firewall.Blocklist.presets[0].summary
        let input = Firewall.Blocklist.Import(
            id: preset.id,
            name: preset.name,
            source: preset.source,
            text: "127.0.0.1 localhost\n0.0.0.0 ads.test\n0.0.0.0 ads.test\ntracker.test"
        )
        #expect(runtime.handle(.blocklist(.replace(input))).error == nil)
        #expect(runtime.snapshot().blocklists?.first?.domainCount == 2)
        #expect(!runtime.isBlocked(app: "/app", host: "ads.test", address: "192.0.2.1"))
        _ = runtime.handle(.blocklist(.toggle(preset.id)))
        #expect(runtime.isBlocked(app: "/app", host: "sub.ads.test", address: "192.0.2.1"))
        let decision = runtime.decision(app: "/app", host: "sub.ads.test", address: "192.0.2.1")
        #expect(decision.blocklist == preset.id)
        #expect(decision.rule == nil)
        #expect(!runtime.isBlocked(app: "/app", host: "notads.test", address: "192.0.2.1"))
        let second = Firewall.Blocklist.presets[1].summary
        _ = runtime.handle(.blocklist(.replace(.init(
            id: second.id,
            name: second.name,
            source: second.source,
            text: "ads.test",
            enable: true
        ))))
        _ = runtime.handle(.blocklist(.toggle(preset.id)))
        #expect(runtime.isBlocked(app: "/app", host: "ads.test", address: "192.0.2.1"))
        _ = runtime.handle(.blocklist(.toggle(second.id)))
        #expect(!runtime.isBlocked(app: "/app", host: "ads.test", address: "192.0.2.1"))
        #expect(runtime.snapshot().rules == [manual])
        #expect(runtime.isBlocked(app: "/app", host: "manual.test", address: "192.0.2.1"))
    }

    @Test func failed_updates_retain_cached_policy_and_restart_restores_lists() throws {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = try Firewall.Runtime(directory: directory)
        let preset = Firewall.Blocklist.presets[0].summary
        _ = runtime.handle(.blocklist(.replace(.init(
            id: preset.id,
            name: preset.name,
            source: preset.source,
            text: "ads.test",
            enable: true
        ))))
        let before = try Data(contentsOf: directory.appendingPathComponent("blocklists.json"))
        for text in ["<html>server error</html>", "# empty", "||ads.test^$third-party"] {
            let reply = runtime.handle(.blocklist(.replace(.init(
                id: preset.id,
                name: preset.name,
                source: preset.source,
                text: text
            ))))
            #expect(reply.error != nil)
            #expect(try Data(contentsOf: directory.appendingPathComponent("blocklists.json")) ==
                before)
        }
        let restored = try Firewall.Runtime(directory: directory)
        #expect(restored.isBlocked(app: "/app", host: "ads.test", address: "192.0.2.1"))
        #expect(restored.handle(.blocklist(.read(preset.id))).blocklist?.domains == ["ads.test"])
        #expect(!String(decoding: try JSONEncoder().encode(restored.snapshot()), as: UTF8.self)
            .contains("ads.test"))
        #expect((try FileManager.default
                .attributesOfItem(atPath: directory.appendingPathComponent("blocklists.json")
                    .path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}

@Test func anchored_domain_feeds_are_supported_without_silently_ignoring_exceptions_or_url_rules(
) throws {
    #expect(try Firewall.Runtime
        .parseBlocklist("[Adblock Plus]\n! Publisher metadata\n||ads.test^\n||tracker.test^\n") == [
            "ads.test",
            "tracker.test"
        ])
    for rule in ["@@||ads.test^", "||ads.test^$third-party", "||ads.test/path^", "||*.ads.test^"] {
        #expect(throws: (any Error).self) { try Firewall.Runtime.parseBlocklist(rule) }
    }
}

@Test func dns_owner_names_with_underscores_in_community_feeds_match_exact_labels() throws {
    #expect(Firewall.Hostname
        .normalize("chicago_cbslocal.us.intellitxt.com") == "chicago_cbslocal.us.intellitxt.com")
    #expect(Firewall.Hostname.matches(
        "sub.chicago_cbslocal.us.intellitxt.com",
        domain: "chicago_cbslocal.us.intellitxt.com"
    ))
    #expect(Firewall.Hostname.normalize("smaato\\.example.test") == nil)
}
