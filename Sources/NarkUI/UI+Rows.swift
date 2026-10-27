import Firewall
import Foundation
import SwiftTUI
import Vocabulary

extension UI {

    public struct Application<Concept: L & I_nark_ui_component_application>: View {

        public let concept: K<Concept>
        public let name: String
        public let count: Int
        public let blocked: Bool
        public let activity: Double
        public let activityMaximum: Double
        public init(
            _ concept: K<Concept>,
            name: String,
            count: Int,
            blocked: Bool = false,
            activity: Double = 0,
            activityMaximum: Double = 1
        ) {
            self.concept = concept
            self.name = name
            self.count = count
            self.blocked = blocked
            self.activity = activity
            self.activityMaximum = activityMaximum
        }

        public var body: some View {
            Columns(.application) {
                Text(name.formatted(.terminalText))
            } middle: {
                ActivityMeter(concept.activity, value: activity, maximum: activityMaximum)
            } trailing: {
                Text("\(count)")
                    .foregroundStyle(blocked ? .theme.danger : .theme.muted)
            }
            .tag((try? concept[as: String.self]) ?? concept.__)
        }
    }

    public struct Connection<Concept: L & I_nark_ui_component_connection>: View {

        public let concept: K<Concept>
        public let connection: Firewall.Connection
        public let policyBlocks: Bool
        public init(_ concept: K<Concept>, connection: Firewall.Connection, policyBlocks: Bool) {
            self.concept = concept
            self.connection = connection
            self.policyBlocks = policyBlocks
        }

        public var body: some View {
            Columns(.connection) {
                HStack(spacing: 1) {
                    Direction(concept.direction, value: connection.direction)
                    Text(connection.destination.formatted(.terminalText))
                }
            } middle: {
                Text("\(connection.count)")
                    .foregroundStyle(.theme.muted)
            } trailing: {
                Text(policyBlocks ? "BLOCK" : "ALLOW")
                    .foregroundStyle(policyBlocks ? .theme.danger : .theme.success)
            }
            .tag((try? concept[as: String.self]) ?? concept.__)
        }
    }

    public struct Rule<Concept: L & I_nark_ui_component_rule>: View {

        public let concept: K<Concept>
        public let rule: Firewall.Rule
        public init(_ concept: K<Concept>, rule: Firewall.Rule) {
            self.concept = concept
            self.rule = rule
        }

        public var body: some View {
            let application = rule.app.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "All applications"
            Columns(.rule) {
                Text((rule.domain ?? "All destinations").formatted(.terminalText))
            } middle: {
                Text(application.formatted(.terminalText))
                    .foregroundStyle(.theme.muted)
            } trailing: {
                Text(rule.enabled ? "BLOCK" : "OFF")
                    .foregroundStyle(rule.enabled ? .theme.danger : .theme.muted)
            }
            .tag((try? concept[as: String.self]) ?? concept.__)
        }
    }

}
