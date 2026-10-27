import Firewall
import Foundation
import Monitor
import NarkUI
import SwiftTUI
import Vocabulary

/// Geometry stays independent of the cursor. Each panel observes its own inputs.
struct MonitorHome: View {

    let session: MonitorFeature.Session
    let width: Int
    let height: Int
    let trafficHeight: Int

    var body: some View {
        let sidebarWidth = min(52, max(32, width * 2 / 5))
        VStack(alignment: .leading, spacing: 0) {
            HomeTraffic(session: session)
                .frame(height: trafficHeight)
            HStack(alignment: .top, spacing: 1) {
                HomeSidebar(session: session, width: sidebarWidth, height: height - trafficHeight)
                HomeMap(session: session, width: width - sidebarWidth - 1, height: height - trafficHeight)
            }
            .frame(height: height - trafficHeight)
        }
        .frame(height: height)
    }
}

private struct HomeTraffic: View {

    let session: MonitorFeature.Session

    var body: some View {
        let focus = session.store.content.home.focus(session.store.home.selection)
        let node = focus.node
        let scope = node.kind == .all
            ? nil
            : node.scope.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? node.title
        MonitorTraffic(session: session, samples: focus.samples, scope: scope)
    }
}

private struct HomeSidebar: View {

    let session: MonitorFeature.Session
    let width: Int
    let height: Int

    var body: some View {
        DashboardPanel(title: "applications", accent: .theme.separator) {
            UI.Columns(.application, isHeader: true) {
                Text("  APPLICATION")
            } middle: {
                Text("RECENT")
            } trailing: {
                Text("FLOWS")
            }
            .foregroundStyle(.theme.muted)
            HomeRows(session: session, width: width, height: max(1, height - 5))
            Text("←/→ fold · enter expand / inspect")
                .foregroundStyle(.theme.muted)
                .lineLimit(1)
        }
        .frame(width: width)
    }
}

private struct HomeRows: View {

    let session: MonitorFeature.Session
    let width: Int
    let height: Int

    var body: some View {
        let rows = session.store.outline
        let maximum = session.store.content.home.maximumRecent
        let commands = MonitorCommands(session: session)
        UI.List(
            rows,
            row: nark.ux.monitor.home.tree.row,
            id: \.id,
            selection: session.store.home.selection,
            height: height,
            selectionEvent: session.store.home.selectionEvent,
            positions: session.store.outlinePositions,
            focusOnArrival: true
        ) { concept, row in
            UI.TreeRow(
                concept,
                title: row.node.title,
                depth: row.depth,
                hasChildren: row.node.hasChildren,
                expanded: row.expanded,
                count: row.node.count,
                blocked: row.node.policy == .block,
                mixed: row.node.policy == .mixed,
                activity: [.all, .application, .system, .service].contains(row.node.kind)
                    ? row.node.recent
                    : nil,
                activityMaximum: maximum,
                directions: [.destination, .connection].contains(row.node.kind)
                    ? row.node.directions
                    : [],
                width: width - 4
            )
        }
        .onKeyPress { key, selection in
            commands.treeKey(key, selection: selection)
        }
    }
}

private struct HomeMap: View {

    let session: MonitorFeature.Session
    let width: Int
    let height: Int

    var body: some View {
        let presentation = session.store.homePresentation
        let selected = presentation.selected
        let destinations = presentation.destinations
        let peerCount = presentation.peerCount
        let policyStyle: ThemeShapeStyle = switch selected.policy {
            case .allow:
                .theme.tint
            case .block:
                .theme.danger
            case .mixed:
                .theme.warning
        }
        DashboardPanel(title: selected.title.formatted(.terminalText), accent: policyStyle) {
            UI.WorldMap(
                nark.ux.monitor.map,
                destinations: destinations.map {
                    .init(
                        code: $0.code,
                        highlighted: $0.highlighted,
                        blocked: $0.focusedCount > 0 && $0.blocked == $0.focusedCount,
                        mixed: $0.blocked > 0 && $0.blocked < $0.focusedCount
                    )
                },
                size: .init(width: max(0, width - 2), height: max(1, height - 8))
            )
            .frame(height: max(1, height - 8))
            Text(
                "Policy: \(selected.policy.rawValue) · \(selected.count) retained flows · \(peerCount) peers · l full list"
            )
            .foregroundStyle(policyStyle)
            .lineLimit(1)
            HStack {
                Text("● allowed")
                    .foregroundStyle(.theme.success)
                Text("● blocked")
                    .foregroundStyle(.theme.danger)
                Text("● mixed")
                    .foregroundStyle(.theme.warning)
            }
            .lineLimit(1)
            Text(
                session.store.locationError.map { "Country lookup: " + $0.formatted(.terminalText) }
                    ?? "Country centres · DB-IP / Natural Earth · offline"
            )
            .foregroundStyle(.theme.muted)
            .lineLimit(1)
            Text("↗ outgoing · ↙ incoming · ↔ both")
                .foregroundStyle(.theme.muted)
                .lineLimit(1)
        }
    }
}
