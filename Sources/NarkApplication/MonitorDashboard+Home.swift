import Firewall
import Foundation
import Monitor
import NarkUI
import SwiftTUI
import Vocabulary

struct MonitorHome: View {

    let session: MonitorFeature.Session
    let presentation: MonitorFeature.HomePresentation
    let width: Int
    let height: Int
    private var commands: MonitorCommands {
        .init(session: session)
    }

    var body: some View {
        let tree = presentation.tree
        let rows = tree.visible(session.store.home)
        let selected = presentation.selected
        let focused = presentation.focusedRows
        let policyStyle: ThemeShapeStyle = switch selected.policy {
            case .allow:
                .theme.tint
            case .block:
                .theme.danger
            case .mixed:
                .theme.warning
        }
        let maximum = tree.roots.compactMap { tree.nodes[$0]?.recent }.max() ?? 0
        let sidebarWidth = min(52, max(32, width * 2 / 5))
        HStack(alignment: .top, spacing: 1) {
            DashboardPanel(title: "applications", accent: .theme.separator) {
                UI.Columns(.application, isHeader: true) {
                    Text("  APPLICATION")
                } middle: {
                    Text("RECENT")
                } trailing: {
                    Text("FLOWS")
                }
                .foregroundStyle(.theme.muted)
                UI.List(
                    rows,
                    row: nark.ux.monitor.home.tree.row,
                    id: \.id,
                    selection: session.store.home.selection,
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
                        width: sidebarWidth - 4
                    )
                }
                .frame(height: max(1, height - 5))
                .onKeyPress {
                    commands.treeKey($0)
                }
                Text("←/→ fold · enter expand / inspect")
                    .foregroundStyle(.theme.muted)
                    .lineLimit(1)
            }
            .frame(width: sidebarWidth)
            DashboardPanel(title: selected.title.formatted(.terminalText), accent: policyStyle) {
                let destinations = presentation.destinations
                UI.WorldMap(nark.ux.monitor.map, destinations: destinations.map {
                    .init(
                        code: $0.code,
                        highlighted: $0.highlighted,
                        blocked: $0.focusedCount > 0 && $0.blocked == $0.focusedCount,
                        mixed: $0.blocked > 0 && $0.blocked < $0.focusedCount
                    )
                })
                .frame(height: max(1, height - 8))
                Text(
                    "Policy: \(selected.policy.rawValue) · \(selected.count) retained flows · \(Set(focused.map(\.destination)).count) peers · l full list"
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
                Text(session.store
                    .locationError
                    .map { "Country lookup: " + $0.formatted(.terminalText) } ??
                    "Country centres · DB-IP / Natural Earth · offline")
                    .foregroundStyle(.theme.muted)
                    .lineLimit(1)
                Text("↗ outgoing · ↙ incoming · ↔ both")
                    .foregroundStyle(.theme.muted)
                    .lineLimit(1)
            }
        }
        .frame(height: height)
    }
}
