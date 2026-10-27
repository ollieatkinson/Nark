extension UI {

    /// Ordinal bounds for a collection of single-line terminal rows.
    struct Viewport: Equatable, Sendable {

        private(set) var offset = 0

        func range(count: Int, height: Int) -> Range<Int> {
            let height = max(1, height)
            let lower = min(offset, max(0, count - height))
            return lower ..< (lower + min(max(1, height), count - lower))
        }

        mutating func clamp(count: Int, height: Int) {
            offset = min(offset, max(0, count - max(1, height)))
        }

        mutating func reveal(_ index: Int?, count: Int, height: Int) {
            let height = max(1, height)
            clamp(count: count, height: height)
            guard let index, (0 ..< count).contains(index) else {
                return
            }
            if index < offset {
                offset = index
            } else if index >= offset + height {
                offset = index - height + 1
            }
        }

        @discardableResult mutating func scroll(by delta: Int, count: Int, height: Int) -> Bool {
            let maximum = max(0, count - max(1, height))
            let start = min(offset, maximum)
            let step = delta > 0 ? min(delta, maximum - start) : max(delta, -start)
            offset = start + step
            return offset != start
        }
    }
}
