import SwiftTUI
import Vocabulary

extension UI {

    /// Terminal components that can share a collection's text layout.
    @MainActor public protocol TextRowContent: View {

        var textRow: TextRow { get }
        var rowActions: [TextRowAction] { get }
    }

    public struct TextRowAction: Equatable, Sendable {

        public let columns: Range<Int>
        private let detail: EventDetail
        private let conceptType: ObjectIdentifier
        private let makeEvent: @Sendable () -> Event

        public var event: Event {
            makeEvent()
        }

        public init<Concept: L>(columns: Range<Int>, concept: K<Concept>) {
            self.columns = columns
            detail = concept.detail
            conceptType = ObjectIdentifier(Concept.self)
            makeEvent = { Event(concept) }
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.columns == rhs.columns && lhs.detail == rhs.detail && lhs.conceptType == rhs.conceptType
        }
    }
}

public extension UI.TextRowContent {

    var rowActions: [UI.TextRowAction] {
        []
    }
}

extension UI.TextRow: UI.TextRowContent {

    public var textRow: Self {
        self
    }
}
