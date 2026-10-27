import Firewall
import Foundation

extension MonitorFeature.State {

    public var activityTree: ActivityTree {
        (page == .activity ? content.list : content.home).tree
    }

    func node(_ id: String) -> ActivityTree.Node? {
        activityTree.nodes[id]
    }

    public var homePresentation: MonitorFeature.HomePresentation {
        content.homePresentation(selection: home.selection)
    }

    public var focusedTitle: String {
        home.selection == ActivityTree.all ? "All applications" : focusedNode?.title ?? "All applications"
    }

    public var focusedNode: ActivityTree.Node? {
        node(home.selection)
    }

    public var focusedRows: [Firewall.Connection] {
        (page == .activity ? content.list : content.home).focus(home.selection).rows
    }

    public var connectionPositions: [String: Int]? {
        selectedApplication == nil ? listFocus.stringPositions : nil
    }

    public var commandConnection: Firewall.Connection? {
        if page == .home || page == .map {
            guard let node = focusedNode,
                  node.kind == .destination || node.kind == .connection else {
                return nil
            }
            return focusedRows.first
        }
        return selectedConnection
    }

    public var mapDestinations: [MonitorFeature.MapDestination] {
        let index = page == .activity ? content.list : content.home
        return index.destinations(for: index.focus(home.selection))
    }

}

extension MonitorFeature.Content {

    public func homePresentation(selection: String) -> MonitorFeature.HomePresentation {
        let focus = home.focus(selection)
        return .init(
            selected: .init(focus.node),
            destinations: home.destinations(for: focus),
            peerCount: focus.peerCount
        )
    }
}

extension MonitorFeature {

    /// Derive one coherent home frame. Tree, map and summary share the same index.
    public struct HomePresentation: Equatable, Sendable {

        public let selected: ActivityTree.Row.Summary
        public let destinations: [MapDestination]
        public let peerCount: Int
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
