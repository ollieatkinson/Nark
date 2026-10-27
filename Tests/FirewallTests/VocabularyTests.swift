import Firewall
import Foundation
import Testing
import Vocabulary

@Suite struct VocabularyTests {

    @Test func flow_inherits_attribution_direction_transport_and_decision() {
        // These generic constraints fail to compile if Lexicon composition is removed.
        func attributed<T: I_nark_network_type_attributed>(_ concept: T) -> String {
            concept.application.path.debugDescription
        }
        func directed<T: I_nark_network_type_directed>(_ concept: T) -> String {
            concept.direction.outbound.debugDescription
        }
        func transported<T: I_nark_network_type_transported>(_ concept: T) -> String {
            concept.transport.tcp.debugDescription
        }
        func decided<T: I_nark_policy_type_decided>(_ concept: T) -> String {
            concept.decision.verdict.drop.debugDescription
        }
        #expect(attributed(nark.filter.flow) == "nark.filter.flow.application.path")
        #expect(directed(nark.filter.flow) == "nark.filter.flow.direction.outbound")
        #expect(transported(nark.filter.flow) == "nark.filter.flow.transport.tcp")
        #expect(decided(nark.filter.flow) == "nark.filter.flow.decision.verdict.drop")
        #expect(
            decided(nark.filter.activity) == "nark.filter.activity.decision.verdict.drop"
        )
        #expect(
            nark.filter.policy.rule.match.destination.hostname.debugDescription
                == "nark.filter.policy.rule.match.destination.hostname"
        )
    }

    @Test func feature_rows_compose_ui_components_and_inherit_control_events() throws {
        func direction<T: I_nark_ui_component_direction>(_ component: T) -> String {
            component.inbound.debugDescription
        }
        #expect(direction(nark.ux.monitor.connections.row.direction) ==
            "nark.ux.monitor.connections.row.direction.inbound")
        #expect(direction(nark.ux.monitor.home.tree.row.direction) ==
            "nark.ux.monitor.home.tree.row.direction.inbound")
        func selection<T: I_nark_ui_type_control>(_ control: T) -> String {
            control.event.select.debugDescription
        }
        func application<T: I_nark_ui_component_application>(_ component: T) -> String {
            component.path.debugDescription
        }
        #expect(selection(nark.ui.component.application) ==
            "nark.ui.component.application.event.select")
        #expect(selection(nark.ux.monitor.applications.row) ==
            "nark.ux.monitor.applications.row.event.select")
        #expect(application(nark.ux.monitor.applications.row) ==
            "nark.ux.monitor.applications.row.path")
        #expect(selection(nark.ux.monitor.rules.add) == "nark.ux.monitor.rules.add.event.select")

        let event = Event(nark.ux.monitor.applications.row["/usr/bin/curl"].event.select)
        #expect(event.matches((any I_nark_ui_type_action).self))
        #expect(event.matches((any I_nark_ui_type_control_event_select).self))
        #expect(try event[nark.ux.monitor.applications.row, as: String.self] == "/usr/bin/curl")
    }

    @Test func verdict_events_carry_flow_and_matching_rule_on_shared_bus() async throws {
        let runtime = try Firewall.Runtime()
        let stream = runtime.events.stream
        let rule = try Firewall.Rule(domain: "example.com")
        _ = runtime.handle(.add(rule))
        let connection = Firewall.Connection(
            app: "/usr/bin/curl", host: "api.example.com", address: "192.0.2.1", port: "443",
            transport: "TCP", blocked: false
        )
        let decision = runtime.evaluate(connection)
        #expect(decision.verdict == .drop)
        #expect(decision.rule == rule.id)
        runtime.events.finish()
        var iterator = stream.makeAsyncIterator()
        let event = try #require(await iterator.next())
        #expect(event.matches(nark.filter.flow.decision.verdict.drop))
        let observed: Firewall.Connection = try event[
            nark.filter.flow, as: Firewall.Connection.self
        ]
        let observedDecision: Firewall.Decision = try event[
            nark.filter.flow.decision, as: Firewall.Decision.self
        ]
        #expect(observed.app == connection.app)
        #expect(observed.direction == .outbound)
        #expect(observed.blocked)
        #expect(observedDecision == decision)
        #expect(await iterator.next() == nil)
    }
}
