import Foundation
import SwiftTUI
import Vocabulary

extension UI {

    /// A mirrored upload/download history. Values are bytes per second; both axes share a scale.
    public struct TrafficChart<Concept: L & I_nark_ui_component_chart>: View, Equatable {

        @Environment(\.terminalAppearance) private var appearance
        public let concept: Concept
        public let sent: [Double]
        public let received: [Double]
        public init(_ concept: Concept, sent: [Double], received: [Double]) {
            self.concept = concept
            self.sent = sent
            self.received = received
        }

        nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.concept == rhs.concept && lhs.sent == rhs.sent && lhs.received == rhs.received
        }

        public var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text("↑ " + UI.bytes(sent.last ?? 0) + "/s")
                        .foregroundStyle(.theme.upload)
                    Spacer()
                    Text("↓ " + UI.bytes(received.last ?? 0) + "/s")
                        .foregroundStyle(.theme.download)
                }
                Canvas(TrafficDrawing(sent: sent, received: received, theme: appearance.synthesizedTheme()))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text(
                        sent.isEmpty
                            ? "Waiting for byte reports"
                            : "5m window · peak " + UI.bytes(max(sent.max() ?? 0, received.max() ?? 0)) + "/s"
                    )
                    Spacer()
                    Text("now")
                }
                .foregroundStyle(.theme.muted)
                .lineLimit(1)
            }
        }
    }

    public static func bytes(_ value: Double) -> String {
        let value = max(0, value)
        if value >= 1_000_000_000 {
            return String(format: "%.1f GB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1f MB", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1f KB", value / 1_000)
        }
        return String(format: "%.0f B", value)
    }

}

private struct TrafficDrawing: CanvasDrawing {

    let sent: [Double]
    let received: [Double]
    let theme: Theme
    func draw(into context: inout CanvasContext) {
        let width = context.size.width
        let height = Double(context.size.height)
        guard width > 0, height > 0 else {
            return
        }
        let middle = height / 2
        let peak = max(1, sent.max() ?? 0, received.max() ?? 0)
        // Bucket to the canvas width, preserving brief peaks when five minutes are compressed.
        let count = max(sent.count, received.count)
        for x in 0 ..< width {
            context.setPixel(at: .init(x: Double(x), y: middle), foreground: theme.muted)
            guard count > 0 else {
                continue
            }
            let start = max(0, x * 300 / width - (300 - count))
            let end = min(count, (x + 1) * 300 / width - (300 - count))
            guard end > start else {
                continue
            }
            let up = sent.dropFirst(start).prefix(end - start).max() ?? 0
            let down = received.dropFirst(start).prefix(end - start).max() ?? 0
            if up > 0 {
                for step in 0 ... max(0, Int(up / peak * middle * 4) - 1) {
                    context.setPixel(
                        at: .init(x: Double(x), y: middle - Double(step + 1) / 4),
                        foreground: theme.info
                    )
                }
            }
            if down > 0 {
                for step in 0 ... max(0, Int(down / peak * middle * 4) - 1) {
                    context.setPixel(
                        at: .init(x: Double(x), y: middle + Double(step + 1) / 4),
                        foreground: theme.link
                    )
                }
            }
        }
    }
}
