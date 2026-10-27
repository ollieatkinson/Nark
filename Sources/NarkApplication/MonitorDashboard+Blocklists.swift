import Firewall
import Foundation
import Monitor
import NarkUI
import SwiftTUI
import Vocabulary

struct BlocklistCatalog: View {

    let session: MonitorFeature.Session
    let height: Int
    private var commands: MonitorCommands {
        .init(session: session)
    }

    var body: some View {
        DashboardPanel(
            title: "blocklists · all apps · space on/off · enter inspect",
            accent: .theme.separator
        ) {
            UI.Columns(.connection, isHeader: true) {
                Text("SOURCE")
            } middle: {
                Text("DOMAINS")
            } trailing: {
                Text("STATE")
            }
            .foregroundStyle(.theme.muted)
            UI.List(
                session.store.blocklists.catalog,
                row: nark.ux.monitor.blocklists.row,
                id: \.id.uuidString,
                selection: session.store.blocklists.selection?.uuidString,
                height: max(1, height - 5),
                selectionEvent: session.store.blocklists.selectionEvent
            ) { _, list in
                UI.Columns(.connection) {
                    Text(list.name.formatted(.terminalText))
                } middle: {
                    Text(list.domainCount == 0 ? "—" : "\(list.domainCount)")
                        .foregroundStyle(.theme.muted)
                } trailing: {
                    Text(list.enabled ? "ON" : "OFF")
                        .foregroundStyle(list.enabled ? .theme.success : .theme.muted)
                }
            }
            .onKeyPress {
                commands.blocklistKey($0)
            }
            if let error = session.store.blocklists.error {
                Text(error.formatted(.terminalText))
                    .foregroundStyle(.theme.danger)
                    .lineLimit(1)
            } else {
                Text(session.store.blocklists.catalogHint)
                    .foregroundStyle(.theme.muted)
                    .lineLimit(1)
            }
        }
    }
}

struct BlocklistBrowser: View {

    let session: MonitorFeature.Session
    let height: Int
    private var commands: MonitorCommands {
        .init(session: session)
    }

    var body: some View {
        DashboardPanel(
            title: "blocklist domains · esc back · space on/off · u refresh",
            accent: .theme.tint
        ) {
            if let list = session.store.blocklists.detail {
                Text(
                    list.summary.name.formatted(.terminalText) + " · \(list.domains.count) domains · "
                        + (list.summary.enabled ? "ON" : "OFF")
                )
                .bold()
                Text(list.summary.source.formatted(.terminalText))
                    .foregroundStyle(.theme.muted)
                    .lineLimit(2)
                Text(list.summary.attribution.formatted(.terminalText))
                    .foregroundStyle(.theme.muted)
                    .lineLimit(1)
                Text(
                    list.summary.updatedAt.map {
                        "Updated " + $0.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    } ?? "Not downloaded yet"
                )
                .foregroundStyle(.theme.muted)
                .lineLimit(1)
                if list.domains.isEmpty {
                    Text("Press u to download this list.")
                        .foregroundStyle(.theme.muted)
                } else {
                    SwiftTUI.List(session.store.blocklists.domains, id: \.self) { domain in
                        Text(domain.formatted(.terminalText))
                    }
                    .listStyle(UI.DenseListStyle())
                    .frame(height: max(1, height - 9))
                }
                if let error = session.store.blocklists.error {
                    Text(error.formatted(.terminalText))
                        .foregroundStyle(.theme.danger)
                        .lineLimit(1)
                }
            }
        }
        .onKeyPress {
            commands.blocklistKey($0)
        }
    }
}
