import Foundation
import SwiftTUI
import Vocabulary

extension UI {

    /// Fixed terminal columns rendered as one styled text leaf. Collection rows
    /// do not need a separate layout subtree for every cell and its modifiers.
    public struct TextRow: View, Equatable {

        public struct Span: Equatable, Sendable {

            public let text: String
            public let style: AnyShapeStyle?
            public init(_ text: String, style: (any ShapeStyle)? = nil) {
                self.text = text
                self.style = style?.eraseToAnyShapeStyle()
            }
        }

        public struct Column: Equatable, Sendable {

            public enum Alignment: Equatable, Sendable {
                case leading
                case trailing
            }

            public let spans: [Span]
            public let width: Int
            public let alignment: Alignment
            public init(
                _ text: String,
                width: Int,
                alignment: Alignment = .leading,
                style: (any ShapeStyle)? = nil
            ) {
                self.init(spans: [Span(text, style: style)], width: width, alignment: alignment)
            }

            public init(spans: [Span], width: Int, alignment: Alignment = .leading) {
                self.spans = spans
                self.width = max(0, width)
                self.alignment = alignment
            }

            /// Use the renderer's Unicode cell widths, including wide glyphs.
            func fitted() -> [Span] {
                guard width > 0 else {
                    return []
                }
                let runs = spans.map { span in
                    (
                        span,
                        layoutText(for: span.text.formatted(.terminalText), width: nil, lineLimit: 1).lines[0].clusters
                    )
                }
                let length = runs.reduce(0) { $0 + $1.1.reduce(0) { $0 + $1.cellWidth } }
                let truncated = length > width
                let budget = truncated ? width - 1 : width
                var used = 0
                var result: [Span] = []
                for (span, clusters) in runs {
                    var text = ""
                    var exhausted = false
                    for cluster in clusters {
                        guard used + cluster.cellWidth <= budget else {
                            exhausted = true
                            break
                        }
                        text.append(cluster.character)
                        used += cluster.cellWidth
                    }
                    if !text.isEmpty {
                        result.append(Span(text, style: span.style))
                    }
                    if exhausted || used >= budget {
                        break
                    }
                }
                if truncated {
                    result.append(Span("…", style: result.last?.style))
                    used += 1
                }
                let padding = Span(String(repeating: " ", count: max(0, width - used)))
                if alignment == .trailing {
                    result.insert(padding, at: 0)
                } else {
                    result.append(padding)
                }
                return result
            }
        }

        public let columns: [Column]
        public let spacing: Int
        public let leadingPadding: Int
        public let accessibilityLabel: String?
        public init(
            _ columns: [Column],
            spacing: Int = 1,
            leadingPadding: Int = 0,
            accessibilityLabel: String? = nil
        ) {
            self.columns = columns
            self.spacing = max(0, spacing)
            self.leadingPadding = max(0, leadingPadding)
            self.accessibilityLabel = accessibilityLabel
        }

        nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.columns == rhs.columns && lhs.spacing == rhs.spacing
                && lhs.leadingPadding == rhs.leadingPadding && lhs.accessibilityLabel == rhs.accessibilityLabel
        }

        public var body: some View {
            text()
                .lineLimit(1)
        }

        /// A value-level row fragment also composes into a collection's text block.
        func text() -> Text {
            var content = Text.StringInterpolation(
                literalCapacity: 128,
                interpolationCount: columns.count
            )
            content.appendLiteral(String(repeating: " ", count: leadingPadding))
            for (index, column) in columns.enumerated() {
                if index > 0 {
                    content.appendLiteral(String(repeating: " ", count: spacing))
                }
                for span in column.fitted() {
                    var text = Text(span.text)
                    if let style = span.style {
                        text = text
                            .foregroundStyle(style)
                    }
                    content.appendInterpolation(text)
                }
            }
            return Text(
                Text.RichContent(stringInterpolation: content),
                semanticMetadata: .init(accessibilityLabel: accessibilityLabel)
            )

        }
    }
}
