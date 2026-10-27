import Firewall
import SwiftTUI
import Vocabulary

extension UI {

    /// A connection's initiator, with a combined marker for grouped peers.
    public struct Direction<Concept: L & I_nark_ui_component_direction>: View {

        public let concept: K<Concept>
        public let directions: Set<Firewall.Direction>
        public init(_ concept: K<Concept>, value: Firewall.Direction) {
            self.concept = concept
            directions = [value]
        }

        public init(_ concept: K<Concept>, directions: Set<Firewall.Direction>) {
            self.concept = concept
            self.directions = directions
        }

        public var body: some View {
            Text(UI.directionSymbol(directions))
                .foregroundStyle(UI.directionStyle(directions))
                .accessibilityLabel(directions.isEmpty
                    ? "Direction unavailable"
                    : directions.map(\.name).sorted().joined(separator: " and "))
        }
    }

    public nonisolated static func directionSymbol(_ directions: Set<Firewall.Direction>) -> String {
        if directions.contains(.unknown) || directions.isEmpty {
            return "?"
        }
        if directions.count > 1 {
            return "↔"
        }
        return directions.contains(.inbound) ? "↙" : "↗"
    }

    nonisolated static func directionStyle(_ directions: Set<Firewall.Direction>) -> ThemeShapeStyle {
        directions.contains(.inbound) ? .theme.tint : .theme.muted
    }
}
