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
            send(event(for: value))
        }

        @MainActor func event<Value: EventValueConvertible>(for value: Value) -> Event {
            switch operation {
                case .select:
                    control.selecting(value)
                case .change:
                    control.changing(value)
            }
        }

        @MainActor func send(_ event: Event) {
            if let focus, !focus.wrappedValue {
                focus.wrappedValue = true
            }
            action(event)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.control.concept == rhs.control.concept
                && lhs.action == rhs.action
                && lhs.operation == rhs.operation
                && (lhs.focus != nil) == (rhs.focus != nil)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(control.concept)
            hasher.combine(action)
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
