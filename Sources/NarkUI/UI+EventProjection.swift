import SwiftTUI
import Vocabulary

extension UI {

    /// A comparable event destination captured by a writable key-path projection.
    /// Identity follows the Lexicon context and bus, rather than a fresh closure.
    struct EventProjection<Concept: L & I_nark_ui_type_control>: Hashable {

        enum Operation: Hashable {
            case select
            case change
        }

        let control: Control<Concept>
        let action: EventAction
        let operation: Operation
        let focus: FocusState<Bool>.Binding?

        @MainActor func send<Value: EventValueConvertible>(_ value: Value) {
            focus?.wrappedValue = true
            switch operation {
                case .select:
                    action(control.selecting(value))
                case .change:
                    action(control.changing(value))
            }
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.control.concept == rhs.control.concept
                && lhs.action.sourceIdentity == rhs.action.sourceIdentity
                && lhs.operation == rhs.operation
                && (lhs.focus != nil) == (rhs.focus != nil)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(control.concept)
            hasher.combine(action.sourceIdentity)
            hasher.combine(operation)
            hasher.combine(focus != nil)
        }
    }
}

extension UI.Control {

    @MainActor func projection(
        _ operation: UI.EventProjection<Concept>.Operation,
        using action: UI.EventAction,
        focus: FocusState<Bool>.Binding? = nil
    ) -> UI.EventProjection<Concept> {
        .init(control: self, action: action, operation: operation, focus: focus)
    }
}

extension EventValueConvertible {

    @MainActor subscript<Concept>(emitting projection: UI.EventProjection<Concept>) -> Self {
        get { self }
        set {
            self = newValue
            projection.send(newValue)
        }
    }
}

extension Optional where Wrapped: EventValueConvertible {

    @MainActor subscript<Concept>(emitting projection: UI.EventProjection<Concept>) -> Self {
        get { self }
        set {
            self = newValue
            if let newValue {
                projection.send(newValue)
            }
        }
    }
}
