import Firewall
import Foundation
import Monitor
import NarkUI
import SwiftTUI
import Vocabulary

struct FlowDetails: View {

    let session: MonitorFeature.Session
    let connection: Firewall.Connection
    var body: some View {
        DashboardPanel(title: "connection details · esc back", accent: .theme.tint) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 1) {
                        UI.Direction(
                            nark.ux.monitor.detail[connection.id.uuidString].direction,
                            value: connection.direction
                        )
                        Text(connection.direction.name + " · " + connection.destination.formatted(.terminalText))
                            .bold()
                            .foregroundStyle(.theme.tint)
                    }
                    property("Executable", connection.app)
                    HStack {
                        property("Address", connection.address)
                        property("Port / transport", "\(connection.port) / \(connection.transport)")
                    }
                    HStack {
                        property("Observed flows", "\(connection.count)")
                        property(
                            "Last observed",
                            connection.lastSeen.formatted(date: .abbreviated, time: .standard)
                        )
                    }
                    property(
                        "Peer country",
                        MonitorFeature.CountrySummary
                            .name(session.store.locations[connection.address] ?? "ZZ")
                    )
                    if let address = connection.localAddress, let port = connection.localPort {
                        property(
                            "Local endpoint (last flow)",
                            (address.contains(":") ? "[\(address)]" : address) + ":" + port
                        )
                    }
                    if let bytes = connection.traffic {
                        property(
                            "Reported traffic",
                            "↑ \(UI.bytes(Double(bytes.sent))) sent · ↓ \(UI.bytes(Double(bytes.received))) received"
                        )
                    } else {
                        property(
                            "Reported traffic",
                            "No byte reports for this retained destination yet"
                        )
                    }
                    property(
                        "Current policy",
                        session.store.snapshot.policyDescription(for: connection)
                    )
                    property("Last decision", connection.blocked ? "Blocked" : "Allowed")
                    Text(
                        "Direction records who initiated the connection. Incoming connections are observed and allowed. Country locations are approximate."
                    )
                    .foregroundStyle(.theme.muted)
                    HStack {
                        if connection.direction == .outbound {
                            UI.Button(nark.ux.monitor.block.destination) {
                                Text("[b block site]")
                            }
                            UI.Button(nark.ux.monitor.block.connection) {
                                Text("[x block app+site]")
                            }
                        }
                        UI.Button(nark.ux.monitor.detail.close) {
                            Text("[esc back]")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func property(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .foregroundStyle(.theme.muted)
            Text(value.formatted(.terminalText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
