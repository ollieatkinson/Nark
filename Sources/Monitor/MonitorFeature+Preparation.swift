import Firewall

extension MonitorFeature.Content {

    /// Capture value inputs on the UI actor; prepare an immutable revision elsewhere.
    struct Preparation: Sendable {

        let revision: MonitorFeature.Content
        private let snapshot: Firewall.Snapshot
        private let previous: Firewall.Snapshot
        private let query: String
        private let field: ConnectionQuery.Field
        private let application: Firewall.Application?
        private let activity: MonitorFeature.Activity
        private let locations: [String: String]

        init(snapshot: Firewall.Snapshot, state: MonitorFeature.State) {
            revision = state.content
            self.snapshot = snapshot
            previous = state.snapshot
            query = state.query
            field = state.searchField
            application = state.application
            activity = state.activity
            locations = state.locations
        }

        @concurrent func content() async -> MonitorFeature.Content {
            var snapshot = snapshot.normalizingConnectionIDs(previous: previous)
            snapshot.rules = previous.rules.updating(with: snapshot.rules)
            return .init(
                snapshot: snapshot,
                query: query,
                field: field,
                application: application,
                activity: activity,
                locations: locations
            )
        }
    }
}
