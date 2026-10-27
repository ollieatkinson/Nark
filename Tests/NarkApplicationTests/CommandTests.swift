import ArgumentParser
import Control
import Firewall
import Foundation
@testable import NarkApplication
import Testing
import TestSupport

@Suite @MainActor struct CommandTests {

    @Test func monitor_is_the_default_command_and_accepts_application_options() throws {
        #expect(try NarkCommand.parseAsRoot([]) is NarkCommand.Watch)
        let watch = try #require(
            NarkCommand.parseAsRoot(["--app", "/usr/bin/true"]) as? NarkCommand.Watch
        )
        let application = try ApplicationPath.resolve("/usr/bin/true")
        #expect(watch.app == application)
    }

    @Test(arguments: [
        ["record", "/usr/bin/true", "--output", "/tmp/Nark reports"],
        ["record", "--output=/tmp/Nark reports", "--app=/usr/bin/true"],
    ])
    func recording_accepts_positional_or_named_application_and_output(arguments: [String]) throws {
        let record = try #require(NarkCommand.parseAsRoot(arguments) as? NarkCommand.Record)
        let application = try ApplicationPath.resolve("/usr/bin/true")
        #expect((record.application ?? record.app) == application)
        #expect(record.output == "/tmp/Nark reports")
    }

    @Test(arguments: [
        ["unknown-command"],
        ["status", "unexpected"],
        ["activate", "unexpected"],
        ["watch", "--app"],
        ["watch", "--unknown"],
        ["block"],
        ["block", "https://example.com/path"],
        ["block", "example.com", "--app", "relative/path"],
        ["block-app", "relative/path"],
        ["remove", "not-a-uuid"],
        ["toggle-blocklist", "not-a-uuid"],
        ["import-blocklist"],
        ["record"],
        ["record", "/usr/bin/true", "--app", "/usr/bin/true"],
        ["record", "/usr/bin/true", "--output"],
    ])
    func invalid_commands_fail_before_connecting_to_the_filter(arguments: [String]) {
        do {
            _ = try NarkCommand.parseAsRoot(arguments)
            Issue.record("Invalid command unexpectedly parsed: \(arguments)")
        } catch {
            #expect(NarkCommand.exitCode(for: error) == .validationFailure)
        }
    }

    @Test func rule_commands_preserve_scope_and_target_the_requested_rule() async throws {
        let runtime = try Firewall.Runtime()
        let client = Firewall.Client(runtime: runtime)
        let block = try #require(NarkCommand.parseAsRoot([
            "block", "Example.COM", "--app=/usr/bin/true",
        ]) as? NarkCommand.Block)
        try await block.run(client: client)
        let rule = try #require(runtime.snapshot().rules.first)
        #expect(rule.app == "/usr/bin/true")
        #expect(rule.domain == "example.com")
        #expect(rule.enabled)

        let toggle = try #require(NarkCommand.parseAsRoot([
            "toggle", rule.id.uuidString,
        ]) as? NarkCommand.Toggle)
        try await toggle.run(client: client)
        #expect(runtime.snapshot().rules.first?.enabled == false)

        let remove = try #require(NarkCommand.parseAsRoot([
            "remove", rule.id.uuidString,
        ]) as? NarkCommand.Remove)
        try await remove.run(client: client)
        #expect(runtime.snapshot().rules.isEmpty)
    }

    @Test func blocklist_commands_toggle_and_remove_the_requested_list() async throws {
        let runtime = try Firewall.Runtime()
        let client = Firewall.Client(runtime: runtime)
        _ = try await client.request(.blocklist(.replace(.init(
            name: "Test list",
            source: "https://example.com/hosts",
            text: "blocked.example"
        ))))
        let list = try #require(runtime.snapshot().blocklists?.first(where: { $0.name == "Test list" }))
        #expect(!list.enabled)

        let toggle = try #require(NarkCommand.parseAsRoot([
            "toggle-blocklist", list.id.uuidString,
        ]) as? NarkCommand.ToggleBlocklist)
        try await toggle.run(client: client)
        #expect(runtime.snapshot().blocklists?.first(where: { $0.id == list.id })?.enabled == true)

        let remove = try #require(NarkCommand.parseAsRoot([
            "remove-blocklist", list.id.uuidString,
        ]) as? NarkCommand.RemoveBlocklist)
        try await remove.run(client: client)
        #expect(runtime.snapshot().blocklists?.contains(where: { $0.id == list.id }) == false)
    }
}
