import Firewall
import Foundation

extension MonitorFeature.State {

    // List filtering must not erase the app/service selected in Home when there
    // are zero matches. Resolve navigation against the unfiltered app scope.
    private var navigationRows: [Firewall.Connection] {
        page == .activity ? scopedRows : matchingRows
    }

    public var activityTree: ActivityTree {
        ActivityTree(
            rows: navigationRows,
            recent: activity.recentFlows,
            isBlocked: snapshot.blocks
        )
    }

    var navigationTree: ActivityTree {
        ActivityTree(
            rows: navigationRows,
            recent: activity.recentFlows,
            expanded: home.expanded,
            isBlocked: snapshot.blocks
        )
    }

    func node(_ id: String) -> ActivityTree.Node? {
        navigationTree.nodes[id] ?? activityTree.nodes[id]
    }

    public var homePresentation: MonitorFeature.HomePresentation {
        .init(
            rows: matchingRows,
            navigation: home,
            activity: activity,
            locations: locations,
            isBlocked: snapshot.blocks
        )
    }

    public var focusedTitle: String {
        home.selection == ActivityTree.all ? "All applications" : focusedNode?.title ?? "All applications"
    }

    public var focusedNode: ActivityTree.Node? {
        node(home.selection)
    }

    public var focusedRows: [Firewall.Connection] {
        guard
            home.selection != ActivityTree.all,
            let selected = focusedNode
        else {
            return matchingRows
        }
        return matchingRows.filter { selected.connections.contains($0.id) }
    }

    public var commandConnection: Firewall.Connection? {
        if page == .home || page == .map {
            guard
                let node = focusedNode,
                node.kind == .destination || node.kind == .connection
            else {
                return nil
            }
            return focusedRows.first
        }
        return selectedConnection
    }

    public var mapDestinations: [MonitorFeature.MapDestination] {
        MonitorFeature.MapDestination.project(
            rows: matchingRows,
            selected: Set(focusedRows.map(\.id)),
            locations: locations,
            isBlocked: snapshot.blocks
        )
    }
}

extension MonitorFeature {

    /// Derive one coherent home frame. Tree, map and summary share the same index.
    public struct HomePresentation: Equatable, Sendable {

        public let tree: ActivityTree
        public let selected: ActivityTree.Node
        public let focusedRows: [Firewall.Connection]
        public let destinations: [MapDestination]
        init(
            rows: [Firewall.Connection],
            navigation: ActivityTree.Navigation,
            activity: Activity,
            locations: [String: String],
            isBlocked: (Firewall.Connection) -> Bool
        ) {
            var index = ActivityTree(
                rows: rows,
                recent: activity.recentFlows,
                expanded: navigation.expanded,
                isBlocked: isBlocked
            )
            if index.nodes[navigation.selection] == nil {
                index = ActivityTree(rows: rows, recent: activity.recentFlows, isBlocked: isBlocked)
            }
            let node = index.nodes[navigation.selection] ?? index.nodes[ActivityTree.all]!
            tree = index
            selected = node
            focusedRows = navigation.selection == ActivityTree.all
                ? rows
                : rows.filter { node.connections.contains($0.id) }
            destinations = MapDestination.project(
                rows: rows,
                selected: node.connections,
                locations: locations,
                isBlocked: isBlocked
            )
        }
    }

    public struct MapDestination: Equatable, Identifiable, Sendable {

        public let code: String
        public let count: Int
        public let highlighted: Bool
        public let blocked: Int
        public let focusedCount: Int
        public var id: String {
            code
        }

        static func project(
            rows: [Firewall.Connection],
            selected: Set<UUID>,
            locations: [String: String],
            isBlocked: (Firewall.Connection) -> Bool
        ) -> [Self] {
            Dictionary(grouping: rows, by: { locations[$0.address] ?? "ZZ" })
                .map { code, rows in
                    let focused = rows.filter { selected.contains($0.id) }
                    return MonitorFeature.MapDestination(
                        code: code,
                        count: rows.reduce(0) { $0 + $1.count },
                        highlighted: !focused.isEmpty,
                        blocked: focused.filter(isBlocked).reduce(0) { $0 + $1.count },
                        focusedCount: focused.reduce(0) { $0 + $1.count }
                    )
                }
                .sorted { $0.code < $1.code }
        }
    }
}
