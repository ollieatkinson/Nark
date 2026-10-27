import Firewall
import Foundation
import Monitor
import NarkUI
import SwiftTUI
import Vocabulary

struct CommunityLists: View {

    let session: MonitorFeature.Session
    let height: Int
    var body: some View {
        DashboardPanel(
            title: "community blocklists · enter add · i paste URL · esc back",
            accent: .theme.tint
        ) {
            HStack {
                Text("Category: " + (session.store.blocklists.category?.rawValue ?? "All") + " [c]")
                Spacer()
                Text("Added lists start off")
                    .foregroundStyle(.theme.muted)
            }
            .frame(height: 1)
            UI.Columns(.community, isHeader: true) {
                Text("LIST")
            } middle: {
                Text("CATEGORIES")
            } trailing: {
                Text("STATE")
            }
            .foregroundStyle(.theme.muted)
            UI.List(
                session.store.blocklists.community,
                row: nark.ux.monitor.blocklists.community.row,
                id: \.id.uuidString,
                selection: session.store.blocklists.selectedCommunity?.id.uuidString,
                height: max(2, height - 12),
                selectionEvent: session.store.blocklists.communitySelectionEvent
            ) { _, source in
                UI.Columns(.community) {
                    Text(source.name.formatted(.terminalText))
                } middle: {
                    Text(source.categories.map(\.shortTitle).joined(separator: " · "))
                        .foregroundStyle(.theme.muted)
                } trailing: {
                    Text(
                        session.store.blocklists.catalog.contains { $0.id == source.id }
                            ? "ADDED"
                            : "—"
                    )
                    .foregroundStyle(.theme.muted)
                }
            }

            .disabled(session.store.blocklists.busy)
            if let source = session.store.blocklists.selectedCommunity {
                Text(source.name.formatted(.terminalText))
                    .bold()
                Text(source.description.formatted(.terminalText))
                    .lineLimit(2)
                Text(source.source.formatted(.terminalText))
                    .foregroundStyle(.theme.muted)
                    .lineLimit(1)
            } else {
                Text("No lists match this category or search.")
                    .foregroundStyle(.theme.muted)
            }
            if let error = session.store.blocklists.error {
                Text(error.formatted(.terminalText))
                    .foregroundStyle(.theme.danger)
                    .lineLimit(1)
            } else {
                Text(session.store.blocklists.communityHint)
                    .foregroundStyle(.theme.muted)
                    .lineLimit(1)
            }
            HStack {
                UI.Button(nark.ux.monitor.blocklists.community.add) {
                    Text("[Enter add / select existing]")
                }
                .disabled(session.store.blocklists.busy || session.store.blocklists.selectedCommunity == nil)
                UI.Button(nark.ux.monitor.blocklists.community.category) {
                    Text("[c category]")
                }
            }
        }
    }
}
