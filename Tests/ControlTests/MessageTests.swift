import Control
import Firewall
import Foundation
import Testing
import Vocabulary

@Suite struct MessageTests {

    @Test func lexicon_messages_round_trip_rules_and_scoped_identifiers() throws {
        let rule = try Firewall.Rule(app: "/usr/bin/curl", domain: "example.com")
        for request in [
            Firewall.Request.snapshot,
            .add(rule),
            .remove(rule.id),
            .toggle(rule.id),
            .importDomains("example.com"),
            .clearHistory,
            .blocklist(.replace(.init(name: "Fixture", source: "/fixture.txt", text: "ads.test"))),
            .blocklist(.toggle(rule.id)),
            .blocklist(.remove(rule.id)),
            .blocklist(.read(rule.id)),
            .recording(
                .start(
                    try Firewall.Application(
                        path: "/Applications/Example.app",
                        scope: .bundle
                    )
                )
            ),
            .recording(.read(.init(id: rule.id, after: 42))),
            .recording(.stop(.init(id: rule.id, after: 42))),
            .recording(.close(rule.id)),
        ] {
            let message = try Message(request)
            let data = try JSONEncoder().encode(message)
            let received = try JSONDecoder().decode(Message.self, from: data)
            let rebuilt = try Message(received.request())
            #expect(rebuilt.event.lemma == message.event.lemma)
            #expect(rebuilt.event.values == message.event.values)
        }
        #expect(try Message(.add(rule)).event.lemma == nark.policy.rule.add.debugDescription)
    }

    @Test func unknown_or_malformed_messages_are_rejected() throws {
        let raw = """
        {"version":1,"event":{"id":1,"description":"nark.policy.rule.add","lemma":"nark.policy.rule.add","values":{}}}
        """
        let message = try JSONDecoder().decode(Message.self, from: Data(raw.utf8))
        #expect(throws: (any Error).self) { try message.request() }
        let unknown = raw.replacingOccurrences(
            of: "nark.policy.rule.add",
            with: "nark.unknown"
        )
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Message.self, from: Data(unknown.utf8)).request()
        }
        let future = raw.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Message.self, from: Data(future.utf8)).request()
        }
    }
}

@Test func large_feed_envelopes_fit_the_bounded_provider_transport() throws {
    let text = String(repeating: "# feed metadata\n", count: 350_000)
    let input = Firewall.Blocklist.Import(name: "Large fixture", source: "/fixture.txt", text: text)
    let data = try JSONEncoder().encode(Message(.blocklist(.replace(input))))
    #expect(data.count < 24_000_000)
    let decoded = try JSONDecoder().decode(Message.self, from: data).request()
    guard case .blocklist(.replace(let rebuilt)) = decoded else {
        Issue.record("Unexpected blocklist envelope")
        return
    }
    #expect(rebuilt.text == text)
}
