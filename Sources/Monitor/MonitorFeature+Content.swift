import Firewall
import Foundation

extension MonitorFeature {

    /// Immutable data for a traffic revision. Moving the cursor never rebuilds it.
    public final class Content: Equatable, Sendable {

        public let snapshot: Firewall.Snapshot
        public let scopedRows: [Firewall.Connection]
        public let home: Index
        public let list: Index
        public let rules: [Firewall.Rule]
        public let rulePositions: [String: Int]
        public let applications: [ApplicationSummary]
        public let blocked: Set<UUID>
        public let samplesByApplication: [String: [Activity.Sample]]

        init(
            snapshot: Firewall.Snapshot = .init(),
            query: String = "",
            field: ConnectionQuery.Field = .all,
            application: Firewall.Application? = nil,
            activity: Activity = .init(),
            locations: [String: String] = [:]
        ) {
            let snapshot = snapshot.normalizingConnectionIDs()
            self.snapshot = snapshot
            let scoped = snapshot.rows.filter { application?.matches($0.app) ?? true }
            scopedRows = scoped
            let blocked = Set(scoped.filter(snapshot.blocks).map(\.id))
            let filter = ConnectionQuery(query, field: field)
            let matching = scoped.filter { row in
                filter.matches(row, isBlocked: { blocked.contains(row.id) })
            }
            self.blocked = blocked
            var samples: [Set<String>?: [Activity.Sample]] = [:]
            func history(_ paths: Set<String>?) -> [Activity.Sample] {
                if let cached = samples[paths] {
                    return cached
                }
                let result = activity.samples(for: paths)
                samples[paths] = result
                return result
            }
            home = Index(
                rows: matching,
                matching: matching,
                blocked: blocked,
                locations: locations,
                recent: activity.recentFlows,
                history: history,
                scoped: application != nil
            )
            list = scoped == matching
                ? home
                : Index(
                    rows: scoped,
                    matching: matching,
                    blocked: blocked,
                    locations: locations,
                    recent: activity.recentFlows,
                    history: history,
                    scoped: application != nil
                )
            rules = snapshot.rules.filter { rule in
                let inScope = application.map { scope in rule.app.map(scope.matches) ?? true } ?? true
                return inScope && (query.isEmpty
                    || "\(rule.app ?? "") \(rule.domain ?? "")".localizedCaseInsensitiveContains(query))
            }
            rulePositions = Dictionary(uniqueKeysWithValues: rules.enumerated().map { index, rule in
                (rule.id.uuidString, index)
            })
            applications = Dictionary(grouping: matching, by: \.app)
                .map { path, rows in
                    ApplicationSummary(path: path, rows: rows, recentFlows: activity.recentFlows(for: path))
                }
                .sorted(by: ApplicationSummary.precedes)
            samplesByApplication = Dictionary(uniqueKeysWithValues: Set(scoped.map(\.app)).map {
                ($0, history([$0]))
            })
        }

        /// A clock tick refreshes meters and histories while retaining membership indices.
        init(previous: Content, activity: Activity) {
            snapshot = previous.snapshot
            scopedRows = previous.scopedRows
            rules = previous.rules
            rulePositions = previous.rulePositions
            blocked = previous.blocked
            var samples: [Set<String>?: [Activity.Sample]] = [:]
            func history(_ paths: Set<String>?) -> [Activity.Sample] {
                if let cached = samples[paths] {
                    return cached
                }
                let result = activity.samples(for: paths)
                samples[paths] = result
                return result
            }
            home = Index(previous: previous.home, history: history)
            list = previous.list === previous.home ? home : Index(previous: previous.list, history: history)
            applications = previous.applications
                .map { $0.updatingRecentFlows(activity.recentFlows(for: $0.path)) }
                .sorted(by: ApplicationSummary.precedes)
            samplesByApplication = Dictionary(uniqueKeysWithValues: previous.samplesByApplication.keys.map {
                ($0, history([$0]))
            })
        }

        public static func == (lhs: Content, rhs: Content) -> Bool {
            if lhs === rhs {
                return true
            }
            return lhs.snapshot == rhs.snapshot
                && lhs.scopedRows == rhs.scopedRows
                && lhs.home == rhs.home
                && lhs.list == rhs.list
                && lhs.rules == rhs.rules
                && lhs.applications == rhs.applications
                && lhs.blocked == rhs.blocked
                && lhs.samplesByApplication == rhs.samplesByApplication
        }

    }

    public final class Index: Equatable, Sendable {

        public let tree: ActivityTree
        public let focuses: [String: Focus]
        public let countries: [MapDestination]
        public let maximumRecent: Double

        init(
            rows: [Firewall.Connection],
            matching: [Firewall.Connection],
            blocked: Set<UUID>,
            locations: [String: String],
            recent: (String) -> Double,
            history: (Set<String>?) -> [Activity.Sample],
            scoped: Bool
        ) {
            let tree = ActivityTree(rows: rows, recent: recent, isBlocked: { blocked.contains($0.id) })
            self.tree = tree
            maximumRecent = tree.roots.compactMap { tree.nodes[$0]?.recent }.max() ?? 0
            let leaves = Dictionary(uniqueKeysWithValues: tree.nodes.values.compactMap { node in
                node.connection.map { ($0.id, node.id) }
            })
            var members = [ActivityTree.all: matching]
            // Append in snapshot order so a focused list retains its ordering.
            for row in matching {
                var id = leaves[row.id]
                while let current = id, let node = tree.nodes[current] {
                    members[current, default: []].append(row)
                    id = node.parent
                }
            }
            focuses = tree.nodes.mapValues { node in
                let rows = members[node.id, default: []]
                let paths: Set<String>? = node.kind == .all && !scoped ? nil : Set(rows.map(\.app))
                return Focus(
                    node: node,
                    rows: rows,
                    locations: locations,
                    blocked: blocked,
                    samples: history(paths),
                    samplePaths: paths
                )
            }
            countries = MapDestination.project(
                rows: matching,
                selected: [],
                locations: locations,
                isBlocked: { blocked.contains($0.id) }
            )
        }

        init(previous: Index, history: (Set<String>?) -> [Activity.Sample]) {
            countries = previous.countries
            var recent: [String: Double] = [:]
            for (id, focus) in previous.focuses {
                switch focus.node.kind {
                    case .all, .application, .system, .service:
                        let paths = Set(focus.applications.keys)
                        recent[id] = history(paths).suffix(10).reduce(0) { $0 + $1.flows }
                    case .destination, .connection:
                        break
                }
            }
            let tree = previous.tree.updatingRecentFlows(recent)
            self.tree = tree
            maximumRecent = tree.roots.compactMap { recent[$0] }.max() ?? 0
            focuses = previous.focuses.mapValues { previous in
                var focus = previous
                if let node = tree.nodes[focus.node.id] {
                    focus.node = node
                }
                focus.samples = history(focus.samplePaths)
                return focus
            }
        }

        public func focus(_ id: String) -> Focus {
            focuses[id] ?? focuses[ActivityTree.all]!
        }

        public func destinations(for focus: Focus) -> [MapDestination] {
            countries.map { country in
                let counts = focus.countries[country.code]
                return MapDestination(
                    code: country.code,
                    count: country.count,
                    highlighted: counts != nil,
                    blocked: counts?.blocked ?? 0,
                    focusedCount: counts?.flows ?? 0
                )
            }
        }

        public static func == (lhs: Index, rhs: Index) -> Bool {
            lhs === rhs || (lhs.tree == rhs.tree && lhs.focuses == rhs.focuses && lhs.countries == rhs.countries)
        }
    }

    public struct Focus: Equatable, Sendable {

        struct Country: Equatable, Sendable {

            var flows = 0
            var blocked = 0
        }

        public internal(set) var node: ActivityTree.Node
        public let rows: [Firewall.Connection]
        public let applications: [String: [Firewall.Connection]]
        public let positions: [UUID: Int]
        public let stringPositions: [String: Int]
        public let peerCount: Int
        public internal(set) var samples: [Activity.Sample]
        let samplePaths: Set<String>?
        let countries: [String: Country]

        init(
            node: ActivityTree.Node,
            rows: [Firewall.Connection],
            locations: [String: String],
            blocked: Set<UUID>,
            samples: [Activity.Sample],
            samplePaths: Set<String>?
        ) {
            self.node = node
            self.rows = rows
            self.samples = samples
            self.samplePaths = samplePaths
            applications = Dictionary(grouping: rows, by: \.app)
            positions = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
            stringPositions = Dictionary(uniqueKeysWithValues: rows.enumerated().map { index, connection in
                (connection.id.uuidString, index)
            })
            peerCount = Set(rows.map(\.destination)).count
            var countries: [String: Country] = [:]
            for row in rows {
                let code = locations[row.address] ?? "ZZ"
                countries[code, default: .init()].flows += row.count
                if blocked.contains(row.id) {
                    countries[code, default: .init()].blocked += row.count
                }
            }
            self.countries = countries
        }
    }
}

extension MonitorFeature.State {

    mutating func updateContent(snapshot: Firewall.Snapshot? = nil) {
        installContent(MonitorFeature.Content(
            snapshot: snapshot ?? self.snapshot,
            query: query,
            field: searchField,
            application: application,
            activity: activity,
            locations: locations
        ))
    }

    mutating func installContent(_ content: MonitorFeature.Content) {
        self.content = content
        updateOutline()
    }

    mutating func updateOutline() {
        outline = content.home.tree.visible(home)
        outlinePositions = Dictionary(uniqueKeysWithValues: outline.enumerated().map { ($0.element.id, $0.offset) })
    }

    var listFocus: MonitorFeature.Focus {
        page == .activity ? content.list.focus(home.selection) : content.home.focus(ActivityTree.all)
    }
}
