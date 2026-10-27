import Firewall
import Foundation

/// The activity hierarchy is a projection of observed executable paths and endpoints.
/// It does not infer parent processes or signed identities.
public struct ActivityTree: Equatable, Sendable {

    public static let all = "all"

    public enum Policy: String, Equatable, Sendable {
        case allow = "ALLOW"
        case block = "BLOCK"
        case mixed = "MIXED"
    }

    public enum Kind: Equatable, Sendable {
        case all
        case application
        case system
        case service
        case destination
        case connection
    }

    public struct Navigation: Equatable, Sendable {

        public var selection = ActivityTree.all {
            didSet { selectionEvent = nil }
        }

        public var selectionEvent: UInt?
        public var expanded: Set<String> = []
        public init() {}
    }

    public struct Node: Equatable, Identifiable, Sendable {

        public let id: String
        public let parent: String?
        public let title: String
        public let kind: Kind
        public let scope: Firewall.Application?
        public let connection: Firewall.Connection?
        public let directions: Set<Firewall.Direction>
        public var children: [String] = []
        public var connections: Set<UUID>
        public var count: Int
        public var blocked: Int
        public var recent: Double
        /// Policy for the retained endpoints, separate from their recorded verdicts.
        public var policy: Policy {
            blocked == 0 ? .allow : blocked == count ? .block : .mixed
        }

        public var hasChildren: Bool {
            kind != .all && kind != .connection && !connections.isEmpty
        }
    }

    public struct Row: Equatable, Identifiable, Sendable {

        /// Display rows do not retain endpoint sets, child indices or full connections.
        public struct Summary: Equatable, Sendable {

            public let id: String
            public let title: String
            public let kind: Kind
            public let directions: Set<Firewall.Direction>
            public let count: Int
            public let policy: Policy
            public let recent: Double
            public let hasChildren: Bool

            public init(_ node: Node) {
                id = node.id
                title = node.title
                kind = node.kind
                directions = node.directions
                count = node.count
                policy = node.policy
                recent = node.recent
                hasChildren = node.hasChildren
            }
        }

        public let node: Summary
        public let depth: Int
        public let expanded: Bool
        public var id: String {
            node.id
        }

        init(node: Node, depth: Int, expanded: Bool) {
            self.node = Summary(node)
            self.depth = depth
            self.expanded = expanded
        }
    }

    public private(set) var nodes: [String: Node] = [:]
    public private(set) var roots: [String] = []

    /// `expanded` limits materialization to disclosed branches. Omitting it
    /// builds the complete index for navigation and arbitrary ID lookup.
    public init(
        rows: [Firewall.Connection],
        recent: (String) -> Double = { _ in 0 },
        expanded: Set<String>? = nil,
        isBlocked: (Firewall.Connection) -> Bool = { $0.blocked }
    ) {
        nodes[Self.all] = Node(
            id: Self.all,
            parent: nil,
            title: "All applications",
            kind: .all,
            scope: nil,
            connection: nil,
            directions: Set(rows.map(\.direction)),
            connections: Set(rows.map(\.id)),
            count: rows.reduce(0) { $0 + $1.count },
            blocked: rows.filter(isBlocked).reduce(0) { $0 + $1.count },
            recent: Set(rows.map(\.app)).reduce(0) { $0 + recent($1) }
        )
        let services = Dictionary(grouping: rows, by: \.app)
        let groups = Dictionary(grouping: services.keys, by: Self.group)
        for (group, executables) in groups {
            let groupRows = executables.flatMap { services[$0, default: []] }
            let groupID = Self.key("application", group.path)
            let scope = try? Firewall.Application(
                path: group.path,
                scope: group.bundle ? .bundle : .executable
            )
            nodes[groupID] = Self.node(
                id: groupID,
                parent: nil,
                title: group.title,
                kind: group.system ? .system : .application,
                scope: group.system ? nil : scope,
                rows: groupRows,
                recent: executables.reduce(0) { $0 + recent($1) },
                isBlocked: isBlocked
            )
            roots.append(groupID)
            if let expanded, !expanded.contains(groupID) {
                continue
            }
            for executable in executables.sorted() {
                let serviceRows = services[executable, default: []]
                let serviceScope = try? Firewall.Application(path: executable, scope: .executable)
                // A single executable already has its application row. Bundled helpers
                // and OS services retain a separate, selectable service level.
                let separateService = group.system || executables.count > 1
                let serviceID = separateService ? Self.key("service", executable) : groupID
                if separateService {
                    nodes[serviceID] = Self.node(
                        id: serviceID,
                        parent: groupID,
                        title: URL(fileURLWithPath: executable)
                            .lastPathComponent,
                        kind: .service,
                        scope: serviceScope,
                        rows: serviceRows,
                        recent: recent(executable),
                        isBlocked: isBlocked
                    )
                    nodes[groupID]?.children.append(serviceID)
                    if let expanded, !expanded.contains(serviceID) {
                        continue
                    }
                }
                for (destination, connections) in Dictionary(
                    grouping: serviceRows,
                    by: \.destination
                ) {
                    let destinationID = Self.key("destination", serviceID, destination)
                    nodes[destinationID] = Self.node(
                        id: destinationID,
                        parent: serviceID,
                        title: destination,
                        kind: .destination,
                        scope: serviceScope,
                        rows: connections,
                        isBlocked: isBlocked
                    )
                    nodes[serviceID]?.children.append(destinationID)
                    if let expanded, !expanded.contains(destinationID) {
                        continue
                    }
                    for connection in connections {
                        let id = Self.key("connection", connection.id.uuidString)
                        let address = connection.address.contains(":") ? "[\(connection.address)]" : connection.address
                        nodes[id] = Node(
                            id: id,
                            parent: destinationID,
                            title: "\(address):\(connection.port) · \(connection.transport)",
                            kind: .connection,
                            scope: serviceScope,
                            connection: connection,
                            directions: [connection.direction],
                            connections: [connection.id],
                            count: connection.count,
                            blocked: isBlocked(connection) ? connection.count : 0,
                            recent: 0
                        )
                        nodes[destinationID]?.children.append(id)
                    }
                }
            }
        }
        let values = nodes
        func precedes(_ lhs: String, _ rhs: String) -> Bool {
            guard let a = values[lhs], let b = values[rhs] else {
                return lhs < rhs
            }
            if a.count != b.count {
                return a.count > b.count
            }
            return a.title == b.title ? a.id < b.id : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        roots.sort(by: precedes)
        for (id, node) in values
            where node.children.count > 1 {
            nodes[id]?.children.sort(by: precedes)
        }
    }

    public func visible(_ navigation: Navigation) -> [Row] {
        var result = [Row(node: nodes[Self.all]!, depth: 0, expanded: false)]
        func append(_ id: String, depth: Int) {
            guard let node = nodes[id] else {
                return
            }
            let expanded = navigation.expanded.contains(id)
            result.append(Row(node: node, depth: depth, expanded: expanded))
            if expanded {
                for child in node.children {
                    append(child, depth: depth + 1)
                }
            }
        }
        for root in roots {
            append(root, depth: 0)
        }
        return result
    }

    /// Activity samples change row meters, not the endpoint hierarchy or its ordering.
    func updatingRecentFlows(_ values: [String: Double]) -> Self {
        var tree = self
        for (id, recent) in values {
            tree.nodes[id]?.recent = recent
        }
        return tree
    }

    public func ancestor(of id: String, visibleIn navigation: Navigation) -> String {
        let visible = Set(visible(navigation).map(\.id))
        var candidate: String? = id
        while let id = candidate {
            if visible.contains(id) {
                return id
            }
            candidate = nodes[id]?.parent
        }
        return Self.all
    }

    private static func node(
        id: String,
        parent: String?,
        title: String,
        kind: Kind,
        scope: Firewall.Application?,
        rows: [Firewall.Connection],
        recent: Double = 0,
        isBlocked: (Firewall.Connection) -> Bool
    ) -> Node {
        Node(
            id: id,
            parent: parent,
            title: title,
            kind: kind,
            scope: scope,
            connection: nil,
            directions: Set(rows.map(\.direction)),
            connections: Set(rows.map(\.id)),
            count: rows.reduce(0) { $0 + $1.count },
            blocked: rows.filter(isBlocked).reduce(0) { $0 + $1.count },
            recent: recent
        )
    }

    private struct Group: Hashable {

        let path: String
        let title: String
        var bundle = false
        var system = false
    }

    private static func group(_ executable: String) -> Group {
        let components = executable.split(separator: "/")
        if let index = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) {
            let path = "/" + components.prefix(index + 1).joined(separator: "/")
            return Group(path: path, title: String(components[index].dropLast(4)), bundle: true)
        }
        if [
            "/System/",
            "/usr/libexec/",
            "/usr/bin/",
            "/usr/sbin/",
            "/bin/",
            "/sbin/"
        ].contains(where: executable.hasPrefix) {
            return Group(path: "system", title: "System services", system: true)
        }
        return Group(
            path: executable,
            title: executable == "unknown" ? "Unattributed" : URL(fileURLWithPath: executable).lastPathComponent
        )
    }

    private static func key(_ parts: String...) -> String {
        parts.map { "\($0.utf8.count):\($0)" }
            .joined()
    }
}
