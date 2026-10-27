import SwiftTUI
import Vocabulary

/// Reusable semantic components. Feature composition belongs to the caller.
public enum UI {}

extension UI {

    /// Carries the full Lexicon path and bracketed context into inherited events.
    public struct Control<Concept: L & I_nark_ui_type_control>: Sendable {

        public let concept: K<Concept>
        public init(_ concept: Concept) {
            self.concept = K(concept)
        }

        public init(_ concept: K<Concept>) {
            self.concept = concept
        }

        public var select: Event {
            Event(concept.event.select)
        }

        public var activate: Event {
            Event(concept.event.activate)
        }

        public func activating<Value: EventValueConvertible>(_ value: Value) -> Event {
            Event(concept[value].event.activate)
        }

        public var change: Event {
            Event(concept.event.change)
        }

        public func changing<Value: EventValueConvertible>(_ value: Value) -> Event {
            Event(concept[value].event.change)
        }

        public func selecting<Value: EventValueConvertible>(_ value: Value) -> Event {
            Event(concept[value].event.select)
        }
    }
}

extension UI {

    /// A UI adapter to SwiftLexicon's bus, with one delivery/error policy for all controls.
    public struct EventAction: Sendable {

        private let events: Events?
        private let failure: @MainActor @Sendable (Error) -> Void
        public var isEnabled: Bool {
            events != nil
        }

        var sourceIdentity: ObjectIdentifier? {
            events.map(ObjectIdentifier.init)
        }

        public init(
            events: Events? = nil,
            onFailure: @escaping @MainActor @Sendable (Error) -> Void = { _ in }
        ) {
            self.events = events
            failure = onFailure
        }

        @MainActor public func callAsFunction(_ event: Event) {
            guard let events else {
                return
            }
            do { try events.send(event) } catch { failure(error) }
        }
    }
}

public extension SwiftTUI.EnvironmentValues {

    var eventAction: UI.EventAction {
        get { self[EventActionKey.self] }
        set { self[EventActionKey.self] = newValue }
    }
}

private struct EventActionKey: SwiftTUI.EnvironmentKey {

    static let defaultValue = UI.EventAction()
}

public extension SwiftTUI.View {

    func events(
        _ events: Events,
        onFailure: @escaping @MainActor @Sendable (Error) -> Void
    ) -> some SwiftTUI.View {
        environment(\.eventAction, UI.EventAction(events: events, onFailure: onFailure))
    }
}
