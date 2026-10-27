import Firewall
import Foundation
import Monitor
import NarkUI
import SwiftTUI
import Vocabulary

struct ConnectionsList: View {

    let session: MonitorFeature.Session
    let width: Int
    let height: Int
    var body: some View {
        let columns = UI.ConnectionLayout(width: width - 4, showsEndpoint: width >= 100)
        let rows = session.store.rows
        DashboardPanel(
            title: "connections · " + session.store.focusedTitle.formatted(.terminalText),
            accent: .theme.tint
        ) {
            HStack {
                UI.Select(
                    nark.ux.monitor.search.field,
                    options: ConnectionQuery.Field.allCases.map {
                        .init(
                            $0.rawValue,
                            title: $0.title
                        )
                    },
                    selection: session.store.searchField.rawValue
                )
                Spacer()
                Text("f field")
                    .foregroundStyle(.theme.muted)
            }
            .frame(height: 1)
            columns.header
            ConnectionRows(session: session, columns: columns, height: max(1, height - 6))

            Text(MonitorFeature.State.connectionListHint(count: rows.count))
                .foregroundStyle(.theme.muted)
                .lineLimit(1)
        }
    }
}

private struct ConnectionRows: View {

    let session: MonitorFeature.Session
    let columns: UI.ConnectionLayout
    let height: Int

    var body: some View {
        let rows = session.store.rows
        let blocked = session.store.content.blocked
        UI.List(
            rows,
            row: nark.ux.monitor.connections.row,
            id: \.id.uuidString,
            selection: rows.indices.contains(session.store.selection)
                ? rows[session.store.selection].id.uuidString
                : nil,
            height: height,
            selectionEvent: session.store.selectionEvent,
            positions: session.store.connectionPositions,
            focusOnArrival: true
        ) { _, connection in
            columns.row(connection, policyBlocks: blocked.contains(connection.id))
        }
    }
}
