import Firewall
import Foundation

extension MonitorFeature {

    public struct Activity: Equatable, Sendable {

        public struct Sample: Equatable, Sendable {

            public var received: Double = 0
            public var sent: Double = 0
            public var flows: Double = 0
        }

        private var previous: Firewall.Snapshot?
        private var previousTime: Date?
        public private(set) var applications: [String: [Sample]] = [:]
        public private(set) var count = 0

        public mutating func record(_ snapshot: Firewall.Snapshot, at time: Date) {
            defer { previous = snapshot
                previousTime = time
            }
            guard let previous, let previousTime else {
                return
            }
            let elapsed = time.timeIntervalSince(previousTime)
            guard elapsed > 0 else {
                return
            }
            if previous.traffic?.session != snapshot.traffic?.session {
                applications = [:]
                count = 0
                return
            }
            func counts(_ snapshot: Firewall.Snapshot) -> [String: Int] {
                Dictionary(grouping: snapshot.rows, by: \.app)
                    .mapValues { $0.reduce(0) { $0 + $1.count } }
            }
            let oldCounts = counts(previous)
            let newCounts = counts(snapshot)
            let paths = Set(applications.keys)
                .union(newCounts.keys)
                .union(snapshot.traffic?.applications.keys.map { $0 } ?? [])
            for path in paths {
                let old = previous.traffic?.applications[path] ?? .init()
                let new = snapshot.traffic?.applications[path] ?? .init()
                let sample = Sample(
                    received: Double(max(0, new.received - old.received)) / elapsed,
                    sent: Double(max(0, new.sent - old.sent)) / elapsed,
                    flows: Double(max(
                        0,
                        (newCounts[path] ?? 0) - (oldCounts[path] ?? 0)
                    )) / elapsed
                )
                var samples = applications[path] ?? Array(repeating: Sample(), count: count)
                samples.append(sample)
                applications[path] = Array(samples.suffix(300))
            }
            // Retained paths and byte summaries bound the working set; discard dormant paths.
            applications = applications
                .filter { newCounts[$0.key] != nil || snapshot.traffic?.applications[$0.key] != nil
                }
            count = min(300, count + 1)
        }

        public func samples(for paths: Set<String>? = nil) -> [Sample] {
            var combined = Array(repeating: Sample(), count: count)
            for (path, samples) in applications where paths?.contains(path) ?? true {
                for (index, sample) in samples.suffix(count).enumerated() {
                    combined[index].received += sample.received
                    combined[index].sent += sample.sent
                    combined[index].flows += sample.flows
                }
            }
            return combined
        }

        public func recentFlows(for path: String) -> Double {
            applications[path, default: []].suffix(10).reduce(0) { $0 + $1.flows }
        }
    }
}
