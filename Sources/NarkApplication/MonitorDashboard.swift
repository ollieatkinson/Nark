import Firewall
import Foundation
import Monitor
import NarkUI
import SwiftTUI
import Vocabulary

struct MonitorDashboard: View {

    let session: MonitorFeature.Session
    @Environment(\.requestTermination) private var requestTermination
    @Environment(\.terminalSize) private var terminalSize
    var body: some View {
        Group {
            if terminalSize.width < 70 || terminalSize.height < 20 {
                VStack(alignment: .leading) {
                    Text("NARK")
                        .foregroundStyle(.theme.tint)
                    Text("Resize to at least 70 × 20 cells.")
                    Text("q quit · filter keeps running")
                        .foregroundStyle(.theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable()
                .onKeyPress(.character("q")) { _ in
                    _ = requestTermination()
                    return .handled
                }
            } else {
                MonitorLayout(
                    session: session,
                    width: terminalSize.width,
                    height: terminalSize.height
                )
            }
        }
        .foregroundStyle(.theme.foreground)
        .modifier(UI.TerminalBackground())
    }
}

/// The full-screen host supplies dimensions; interaction owns only prompt state.
private struct MonitorLayout: View {

    let session: MonitorFeature.Session
    let width: Int
    let height: Int
    @Environment(\.requestTermination) private var requestTermination
    @State private var prompt: Prompt?
    @State private var text = ""
    @State private var eventAction: UI.EventAction
    private typealias Prompt = MonitorCommands.Prompt

    init(session: MonitorFeature.Session, width: Int, height: Int) {
        self.session = session
        self.width = width
        self.height = height
        _eventAction = State(initialValue: UI.EventAction(events: session.events) { [weak session] error in
            session?.store.send(.failed(error.localizedDescription))
        })
    }

    private var commands: MonitorCommands {
        MonitorCommands(session: session)
    }

    var body: some View {
        layout(width: width, height: height)
            .environment(\.eventAction, eventAction)
    }

    private func layout(width: Int, height: Int) -> some View {
        let activityHeight = switch height {
            case ..<24:
                6
            case ..<30:
                8
            default:
                10
        }
        return VStack(alignment: .leading, spacing: 0) {
            header
            if let detail = session.store.detail {
                FlowDetails(session: session, connection: detail)
                    .disabled(prompt != nil)
                    .frame(height: height - 4)
            } else if session.store.rulesVisible {
                if session.store.blocklists.communityVisible {
                    CommunityLists(session: session, height: height - 4)
                        .disabled(prompt != nil)
                        .frame(height: height - 4)
                } else if session.store.blocklists.detail != nil {
                    BlocklistBrowser(session: session, height: height - 4)
                        .disabled(prompt != nil)
                        .frame(height: height - 4)
                } else {
                    BlocklistCatalog(session: session, height: 8)
                        .disabled(prompt != nil)
                        .frame(height: 8)
                    manualRules(height: height - 12)
                        .disabled(prompt != nil)
                        .frame(height: height - 12)
                }
            } else if session.store.page == .home || session.store.page == .map {
                MonitorHome(
                    session: session,
                    width: width - 2,
                    height: height - 4,
                    trafficHeight: max(7, activityHeight)
                )
                .disabled(prompt != nil)
            } else {
                if session.store.graphVisible {
                    MonitorTraffic(
                        session: session,
                        samples: session.store.trafficSamples,
                        scope: session.store.trafficScope
                    )
                    .frame(height: activityHeight)
                }
                let graphHeight = session.store.graphVisible ? activityHeight : 0
                let detailsHeight = session.store.graphVisible && height < 24 ? 0 : 5
                let listHeight = height - 4 - graphHeight - detailsHeight
                ConnectionsList(session: session, width: width - 2, height: listHeight)
                    .disabled(prompt != nil)
                    .frame(height: listHeight)
                if detailsHeight > 0 {
                    MonitorSelectionDetails(session: session)
                        .frame(height: detailsHeight)
                }
            }
            footer
        }
        .padding(.horizontal, 1)
        .onKeyPress(perform: keyPress)
        .focusable(prompt == nil && session.store.rulesNeedKeyboardFocus)
    }

    private var header: some View {
        HStack {
            Text("NARK")
                .bold()
                .foregroundStyle(.theme.tint)
            Text(session.store.connected ? "● LIVE" : "○ DISCONNECTED")
                .foregroundStyle(session.store.connected ? .theme.success : .theme.danger)
            Spacer()
            UI.Tab(
                nark.ux.monitor.view.home,
                title: "home",
                selected: (session.store.page == .home || session.store.page == .map) && session.store.detail == nil
            )
            UI.Tab(
                nark.ux.monitor.view.list,
                title: "list",
                selected: session.store.page == .activity && session.store.detail == nil
            )
            UI.Tab(nark.ux.monitor.view.rules, title: "rules", selected: session.store.rulesVisible)
        }
        .frame(height: 2)
    }

    private func manualRules(height: Int) -> some View {
        DashboardPanel(title: "manual rules", accent: .theme.separator) {
            UI.Columns(.rule, isHeader: true) {
                Text("DESTINATION")
            } middle: {
                Text("APPLICATION")
            } trailing: {
                Text("STATE")
            }
            .foregroundStyle(.theme.muted)
            if session.store.rules.isEmpty {
                empty(session.store.emptyRulesMessage)
            }
            UI.List(
                session.store.rules,
                row: nark.ux.monitor.rules.row,
                id: \.id.uuidString,
                selection: selectedRuleID,
                height: max(1, height - 4 - (session.store.rules.isEmpty ? 1 : 0)),
                selectionEvent: session.store.selectionEvent,
                positions: session.store.content.rulePositions
            ) { concept, rule in
                UI.Rule(concept, rule: rule)
            }
            .onKeyPress {
                commands.ruleKey($0)
            }
        }
    }

    private func empty(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = session.store.error {
                Text(error.formatted(.terminalText))
                    .foregroundStyle(.theme.danger)
                    .lineLimit(1)
            } else if let prompt {
                Text(prompt.hint)
                    .foregroundStyle(.theme.muted)
                    .lineLimit(1)
            } else {
                Text(session.store.navigationHint)
                    .foregroundStyle(.theme.muted)
                    .lineLimit(1)
            }
            if let prompt {
                let title = prompt == .search ? session.store.searchTitle : prompt.title
                HStack {
                    Text(title + ":")
                        .foregroundStyle(.theme.tint)
                    Group {
                        if prompt == .search {
                            UI.TextField(nark.ux.monitor.search, text: $text)
                        } else {
                            TextField("", text: $text)
                                .textFieldStyle(.plain)
                        }
                    }
                    .onSubmit {
                        submitPrompt()
                    }
                }
            } else {
                HStack {
                    Text(session.store.searchHint)
                        .foregroundStyle(.theme.muted)
                        .lineLimit(1)
                    Spacer()
                    Text("q quit")
                        .foregroundStyle(.theme.tint)
                }
            }
        }
        .frame(height: 2)
    }

    private var selectedRuleID: String? {
        session.store.rules.indices.contains(session.store.selection)
            ? session.store.rules[session.store.selection].id.uuidString
            : nil
    }

    private func keyPress(_ key: KeyPress) -> KeyPressResult {
        if prompt != nil {
            if key.key == .escape {
                prompt = nil
                return .handled
            }
            return .ignored
        }
        guard key.modifiers.isEmpty else {
            return .ignored
        }
        if session.store.rulesVisible,
           session.store.blocklists.communityVisible,
           case .handled = commands.communityKey(key) {
            return .handled
        }
        if session.store.rulesVisible,
           session.store.blocklists.detail != nil,
           case .handled = commands.blocklistKey(key) {
            return .handled
        }
        switch key.key {
            case .character("q"):
                _ = requestTermination()
            case .character("/"):
                beginPrompt(.search)
            case .character("n"):
                beginPrompt(.domain)
            case .character("i"):
                beginPrompt(.file)
            default:
                return commands.handle(key.key) ? .handled : .ignored
        }
        return .handled
    }

    private func beginPrompt(_ kind: Prompt) {
        text = kind == .search ? session.store.query : ""
        prompt = kind
    }

    private func submitPrompt() {
        guard let prompt else {
            return
        }
        commands.submit(prompt, text: text)
        self.prompt = nil
    }
}

struct DashboardPanel<Accent: ShapeStyle, Content: View>: View {

    let title: String
    let accent: Accent
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .bold()
                .foregroundStyle(accent)
                .lineLimit(1)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 1)
        .padding(.vertical, 1)
        .border(accent, style: .rounded, placement: .inset)
    }
}

struct MonitorTraffic: View {

    let session: MonitorFeature.Session
    let samples: [MonitorFeature.Activity.Sample]
    let scope: String?

    var body: some View {
        DashboardPanel(
            title: "traffic · " + (scope.map { $0.formatted(.terminalText) } ?? "observed socket flows"),
            accent: .theme.tint
        ) {
            UI.TrafficChart(
                nark.ux.monitor.activity,
                sent: samples.map(\.sent),
                received: samples.map(\.received)
            )
            HStack {
                Text(
                    "\(session.store.snapshot.totalAllowed) allowed · \(session.store.snapshot.totalBlocked) blocked"
                )
                Spacer()
                Text(session.store.trafficTrackingSummary)
            }
            .foregroundStyle(.theme.muted)
            .lineLimit(1)
        }
    }
}

private struct MonitorSelectionDetails: View {

    let session: MonitorFeature.Session

    var body: some View {
        DashboardPanel(
            title: session.store.rulesVisible ? "rule scope" : "selection · enter for details",
            accent: .theme.separator
        ) {
            if let row = session.store.selectedConnection {
                Text(row.app.formatted(.terminalText))
                    .lineLimit(1)
                let address = row.address.formatted(.terminalText)
                let endpoint = address.contains(":") ? "[\(address)]" : address
                Text(
                    "\(UI.directionSymbol([row.direction])) \(endpoint):\(row.port.formatted(.terminalText)) · \(row.transport.formatted(.terminalText)) · last observed \(row.blocked ? "blocked" : "allowed")"
                )
                .foregroundStyle(.theme.muted)
                .lineLimit(1)
            } else {
                Text("Select an application or destination.")
                    .foregroundStyle(.theme.muted)
            }
        }
    }
}
