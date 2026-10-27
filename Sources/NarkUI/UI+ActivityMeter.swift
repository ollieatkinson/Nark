import SwiftTUI
import Vocabulary

extension UI {

    /// A quiet, fixed-width meter with the same scale across the collection.
    public struct ActivityMeter<Concept: L & I_nark_ui_component_meter>: View {

        public let concept: K<Concept>
        public let value: Double
        public let maximum: Double
        public init(_ concept: K<Concept>, value: Double, maximum: Double) {
            self.concept = concept
            self.value = value
            self.maximum = maximum
        }

        public var body: some View {
            TextRow([.init(spans: UI.activitySpans(value: value, maximum: maximum), width: 6)])
                .accessibilityLabel("Recent connection activity")
        }
    }

    static func activitySpans(value: Double, maximum: Double) -> [TextRow.Span] {
        let width = 6
        let fraction = value.isFinite && maximum.isFinite ? max(0, min(1, value / max(1, maximum))) : 0
        let filled = fraction > 0 ? max(1, Int((fraction * Double(width)).rounded())) : 0
        return [
            .init(String(repeating: "━", count: filled), style: .theme.success),
            .init(
                String(repeating: "─", count: width - filled),
                style: .theme.separator
            )
        ]
    }
}
