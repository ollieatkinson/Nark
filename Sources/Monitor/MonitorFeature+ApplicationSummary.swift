import Firewall
import Foundation

extension MonitorFeature {

    public struct ApplicationSummary: Equatable, Identifiable, Sendable {

        public let path: String
        public let destinationCount: Int
        public let flowCount: Int
        public private(set) var recentFlows: Double
        public let blockedCount: Int
        public var id: String {
            path
        }

        public var name: String {
            URL(fileURLWithPath: path).lastPathComponent
        }

        func updatingRecentFlows(_ recent: Double) -> Self {
            var summary = self
            summary.recentFlows = recent
            return summary
        }

        static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
            if lhs.recentFlows != rhs.recentFlows {
                return lhs.recentFlows > rhs.recentFlows
            }
            if lhs.flowCount != rhs.flowCount {
                return lhs.flowCount > rhs.flowCount
            }
            return lhs.path < rhs.path
        }

        init(path: String, rows: [Firewall.Connection], recentFlows: Double = 0) {
            self.path = path
            self.recentFlows = recentFlows
            destinationCount = Set(rows.map(\.destination)).count
            flowCount = rows.reduce(0) { $0 + $1.count }
            blockedCount = rows.filter(\.blocked).reduce(0) { $0 + $1.count }
        }
    }
}

extension MonitorFeature.State {

    public var applicationActivityMaximum: Double {
        applications.map(\.recentFlows).max() ?? 0
    }
}
