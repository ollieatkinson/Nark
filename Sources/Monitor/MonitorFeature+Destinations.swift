import Firewall
import Foundation

extension MonitorFeature {

    public struct CountrySummary: Equatable, Identifiable, Sendable {

        public let code: String
        public let flows: Int
        public var id: String {
            code
        }

        public var name: String {
            Self.name(code)
        }

        public static func name(_ code: String) -> String {
            switch code {
                case "LOCAL":
                    "Local network"
                case "ZZ":
                    "Unknown"
                default:
                    Locale(identifier: "en").localizedString(forRegionCode: code) ?? code
            }
        }
    }
}

extension MonitorFeature.State {

    public var trafficScope: String? {
        (selectedApplication ?? focusedNode?.scope?.path ?? application?.path)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    public var trafficSamples: [MonitorFeature.Activity.Sample] {
        let paths = selectedApplication.map { Set([$0]) }
            ?? (home.selection == ActivityTree.all ? nil : Set(focusedRows.map(\.app)))
            ?? application
            .map { app in Set(snapshot.rows.filter { app.matches($0.app) }.map(\.app)) }
        return activity.samples(for: paths)
    }

    public var countries: [MonitorFeature.CountrySummary] {
        Dictionary(grouping: rows, by: { locations[$0.address] ?? "ZZ" })
            .map { MonitorFeature.CountrySummary(
                code: $0.key,
                flows: $0.value.reduce(0) { $0 + $1.count }
            ) }
            .sorted { $0.flows == $1.flows ? $0.code < $1.code : $0.flows > $1.flows }
    }

    public func matchingRules(for connection: Firewall.Connection) -> [Firewall.Rule] {
        snapshot.rules.filter { $0.matches(
            app: connection.app,
            host: connection.host,
            address: connection.address,
            direction: connection.direction
        ) }
    }
}
