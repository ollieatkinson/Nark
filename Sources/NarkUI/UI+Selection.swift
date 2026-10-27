import Observation
import Vocabulary

extension UI {

    /// Keeps the immediate cursor ahead of acknowledgements from the async message bus.
    @Observable @MainActor final class Selection<Value: EventValueConvertible> {

        struct Update: Equatable {

            let value: Value?
            let event: UInt?
        }

        private(set) var value: Value?
        var viewport = Viewport()
        @ObservationIgnored private(set) var latestEvent: UInt?
        @ObservationIgnored private var anchor: Value?

        init(_ value: Value?) {
            self.value = value
        }

        /// Return whether this is a model-directed move rather than our own echo.
        @discardableResult func reconcile(_ update: Update) -> Bool {
            if let latestEvent, let event = update.event, event < latestEvent {
                return false
            }
            let shouldReveal = value != update.value || update.event == nil || update.event != latestEvent
            value = update.value
            latestEvent = update.event
            return shouldReveal
        }

        func move<Data: RandomAccessCollection, Concept>(
            by delta: Int,
            in data: Data,
            id: KeyPath<Data.Element, Value>,
            positions: [Value: Data.Index]?,
            projection: EventProjection<Concept>
        ) {
            guard !data.isEmpty else {
                return
            }
            let next: Data.Index?
            if let current = value.flatMap({ value in
                index(of: value, in: data, id: id, positions: positions)
            }) {
                next = data.index(current, offsetBy: delta, limitedBy: delta > 0 ? data.endIndex : data.startIndex)
                    .flatMap { $0 < data.endIndex ? $0 : nil }
                    ?? (delta > 0 ? data.index(before: data.endIndex) : data.startIndex)
            } else {
                next = delta > 0 ? data.startIndex : data.index(before: data.endIndex)
            }
            if let next, next < data.endIndex {
                self[emitting: projection] = data[next][keyPath: id]
            }
        }

        /// Preserve the first visible identity when traffic inserts or reorders rows.
        func range<Data: RandomAccessCollection>(
            in data: Data,
            id: KeyPath<Data.Element, Value>,
            positions: [Value: Data.Index]?,
            height: Int
        ) -> Range<Int> {
            anchoredViewport(in: data, id: id, positions: positions, height: height)
                .range(count: data.count, height: height)
        }

        func refreshViewport<Data: RandomAccessCollection>(
            in data: Data,
            id: KeyPath<Data.Element, Value>,
            positions: [Value: Data.Index]?,
            height: Int
        ) {
            viewport = anchoredViewport(in: data, id: id, positions: positions, height: height)
            rememberAnchor(in: data, id: id, height: height)
        }

        @discardableResult func scroll<Data: RandomAccessCollection>(
            by delta: Int,
            in data: Data,
            id: KeyPath<Data.Element, Value>,
            positions: [Value: Data.Index]?,
            height: Int
        ) -> Bool {
            refreshViewport(in: data, id: id, positions: positions, height: height)
            let moved = viewport.scroll(by: delta, count: data.count, height: height)
            rememberAnchor(in: data, id: id, height: height)
            return moved
        }

        private func index<Data: RandomAccessCollection>(
            of value: Value,
            in data: Data,
            id: KeyPath<Data.Element, Value>,
            positions: [Value: Data.Index]?
        ) -> Data.Index? {
            if let positions {
                return positions[value]
            }
            return data.firstIndex { $0[keyPath: id] == value }
        }

        private func anchoredViewport<Data: RandomAccessCollection>(
            in data: Data,
            id: KeyPath<Data.Element, Value>,
            positions: [Value: Data.Index]?,
            height: Int
        ) -> Viewport {
            var viewport = viewport
            if let anchor,
               let index = index(of: anchor, in: data, id: id, positions: positions) {
                let offset = data.distance(from: data.startIndex, to: index)
                viewport.scroll(by: offset - viewport.offset, count: data.count, height: height)
            } else {
                viewport.clamp(count: data.count, height: height)
            }
            return viewport
        }

        private func rememberAnchor<Data: RandomAccessCollection>(
            in data: Data,
            id: KeyPath<Data.Element, Value>,
            height: Int
        ) {
            let range = viewport.range(count: data.count, height: height)
            anchor = range.isEmpty ? nil : data[data.index(data.startIndex, offsetBy: range.lowerBound)][keyPath: id]
        }

        func reveal<Data: RandomAccessCollection>(
            in data: Data,
            id: KeyPath<Data.Element, Value>,
            positions: [Value: Data.Index]?,
            height: Int
        ) {
            let index = value.flatMap { value in
                index(of: value, in: data, id: id, positions: positions)
            }
            viewport.reveal(
                index.map { data.distance(from: data.startIndex, to: $0) },
                count: data.count,
                height: height
            )
            rememberAnchor(in: data, id: id, height: height)
        }

        func send<Concept>(_ event: Event, selecting value: Value, using projection: EventProjection<Concept>) {
            self.value = value
            latestEvent = event.id
            projection.send(event)
        }

        subscript<Concept>(emitting projection: EventProjection<Concept>) -> Value? {
            get { value }
            set {
                guard let newValue, newValue != value else {
                    return
                }
                let event = projection.event(for: newValue)
                send(event, selecting: newValue, using: projection)
            }
        }
    }
}
