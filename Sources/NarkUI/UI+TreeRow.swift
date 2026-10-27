import Firewall
import Foundation
import SwiftTUI
import Vocabulary

extension UI {

    /// A reusable disclosure row; the owning experience supplies hierarchy and state.
    public struct TreeRow<Concept: L & I_nark_ui_component_tree_row>: View {

        @Environment(\.eventAction) private var send
        public let concept: K<Concept>
        public let title: String
        public let depth: Int
        public let hasChildren: Bool
        public let expanded: Bool
        public let count: Int
        public let blocked: Bool
        public let mixed: Bool
        public let activity: Double?
        public let activityMaximum: Double
        public let directions: Set<Firewall.Direction>
        public let width: Int
        public init(
            _ concept: K<Concept>,
            title: String,
            depth: Int,
            hasChildren: Bool,
            expanded: Bool,
            count: Int,
            blocked: Bool,
            mixed: Bool = false,
            activity: Double?,
            activityMaximum: Double,
            directions: Set<Firewall.Direction> = [],
            width: Int
        ) {
            self.concept = concept
            self.title = title
            self.depth = depth
            self.hasChildren = hasChildren
            self.expanded = expanded
            self.count = count
            self.blocked = blocked
            self.mixed = mixed
            self.activity = activity
            self.activityMaximum = activityMaximum
            self.directions = directions
            self.width = width
        }

        public var body: some View {
            let indent = min(depth, 8) * 2
            let nameWidth = max(0, width - 7 - (activity == nil ? 0 : 7))
            let disclosure = hasChildren ? (expanded ? "▾ " : "▸ ") : "  "
            let prefix = String(repeating: " ", count: indent) + disclosure
            let policyStyle: ThemeShapeStyle? = blocked ? .theme.danger : mixed ? .theme.warning : nil
            let status = blocked ? "× " : mixed ? "◐ " : ""
            let marker = directions.isEmpty ? "" : UI.directionSymbol(directions) + " "
            let label = (hasChildren ? (expanded ? "Expanded, " : "Collapsed, ") : "")
                + directions.map(\.name).sorted().joined(separator: " and ") + ", " +
                title.formatted(.terminalText) + ", \(count) flows, current policy " + (blocked
                    ? "blocked"
                    : mixed ? "mixed" : "allowed")
            TextRow([
                .init(
                    spans: [.init(prefix, style: policyStyle), .init(
                        marker,
                        style: policyStyle ?? UI.directionStyle(directions)
                    ), .init(status + title, style: policyStyle)],
                    width: nameWidth
                ),
            ] + (activity.map { [.init(
                spans: UI.activitySpans(value: $0, maximum: activityMaximum),
                width: 6
            )] } ?? []) + [
                .init("\(count)", width: 6, alignment: .trailing, style: policyStyle ?? .theme.muted)
            ], accessibilityLabel: label)
                .gesture(SpatialTapGesture()
                    .onEnded { value in
                        if
                            hasChildren,
                            (Double(indent) ..< Double(indent + 2)).contains(value.location.x)
                        {
                            send(Event(concept.disclosure.event.select))
                        } else {
                            send(Event(concept.event.select))
                        }
                    })
        }
    }
}
