import ComposableArchitecture
import Control
import Firewall
import Foundation
import Geography

@Reducer
public struct MonitorFeature {

    public enum Page: Sendable {
        case home
        case activity
        case rules
        case map
    }

    @ObservableState
    public struct State: Equatable {

        /// The traffic and its prepared indices always belong to the same revision.
        public var snapshot: Firewall.Snapshot {
            get { content.snapshot }
            set { updateContent(snapshot: newValue) }
        }

        public var query = "" {
            didSet {
                if oldValue != query {
                    updateContent()
                }
            }
        }

        public var searchField = ConnectionQuery.Field.all {
            didSet {
                if oldValue != searchField {
                    updateContent()
                }
            }
        }

        public var selection = 0 {
            didSet { selectionEvent = nil }
        }

        public var selectionEvent: UInt?
        public var page = Page.home
        public var home = ActivityTree.Navigation() {
            didSet {
                if oldValue.expanded != home.expanded {
                    updateOutline()
                }
            }
        }

        public var graphVisible = false
        public var blocklists = BlocklistsFeature.State()
        public var rulesVisible: Bool {
            get { page == .rules }
            set { page = newValue ? .rules : .activity }
        }

        public var mapVisible: Bool {
            get { page == .map }
            set { page = newValue ? .map : .activity }
        }

        public var detail: Firewall.Connection?
        public var activity = Activity() {
            didSet {
                installContent(Content(previous: content, activity: activity))
            }
        }

        public var locations: [String: String] = [:] {
            didSet { updateContent() }
        }

        public var locationError: String?
        public var selectedApplication: String?
        public var application: Firewall.Application? {
            didSet {
                if oldValue != application {
                    updateContent()
                }
            }
        }

        public var error: String?
        public var connected = false
        public var busy = false
        public internal(set) var content = Content()
        public internal(set) var outline: [ActivityTree.Row] = []
        public internal(set) var outlinePositions: [String: Int] = [:]

        public init() {
            updateOutline()
        }

        public var scopedRows: [Firewall.Connection] {
            content.scopedRows
        }

        public var matchingRows: [Firewall.Connection] {
            content.home.focus(ActivityTree.all).rows
        }

        public var rows: [Firewall.Connection] {
            selectedApplication.map { listFocus.applications[$0, default: []] } ?? listFocus.rows
        }

        public var applications: [ApplicationSummary] {
            content.applications
        }

        public var selectedConnection: Firewall.Connection? {
            rows.indices.contains(selection) ? rows[selection] : nil
        }

        public var rules: [Firewall.Rule] {
            content.rules
        }

        public var itemCount: Int {
            rulesVisible ? rules.count : rows.count
        }
    }

    public enum Action: Sendable {
        case start
        case refresh
        case stop
        case blocklists(BlocklistsFeature.Action)
        case prepareSnapshot(Firewall.Snapshot)
        case received(Firewall.Snapshot, content: Content? = nil, revision: Content? = nil)
        case failed(String)
        case move(Int)
        case search(String)
        case selectSearchField(ConnectionQuery.Field)
        case moveSearchField(Int)
        case switchView
        case toggleMap
        case closeDetail
        case show(Page)
        case selectNode(String, event: UInt? = nil)
        case activateNode(String)
        case toggleNode(String)
        case expandNode(String)
        case collapseNode(String)
        case toggleList
        case toggleGraph
        case openConnection(UUID)
        case tick(Date)
        case locate([String])
        case located([String: String])
        case locationFailed(String)
        case selectApplication(String?)
        case selectConnection(UUID, event: UInt? = nil)
        case selectRule(UUID, event: UInt? = nil)
        case blockDestination
        case blockApp
        case blockAppDestination
        case toggleRule
        case removeRule
        case addDomain(String)
        case importDomains(String)
        case clearHistory
    }

    public let client: Firewall.Client
    public init(client: Firewall.Client) {
        self.client = client
    }

    private enum CancelID {
        case polling
        case request
        case locations
        case preparation
    }

    public var body: some ReducerOf<Self> {
        Scope(state: \.blocklists, action: \.blocklists) { BlocklistsFeature(client: client) }
        Reduce { state, action in
            switch action {
                case .blocklists(.showCommunity):
                    state.page = .rules
                    return .none
                case .blocklists:
                    return .none
                case .start:
                    return .run { send in
                        await send(.refresh)
                        while !Task.isCancelled {
                            try await Task.sleep(for: .seconds(1))
                            await send(.refresh)
                            await send(.tick(Date()))
                        }
                    }
                    .cancellable(id: CancelID.polling, cancelInFlight: true)
                case .stop:
                    return .merge(
                        .cancel(id: CancelID.polling),
                        .cancel(id: CancelID.request),
                        .cancel(id: CancelID.locations),
                        .cancel(id: CancelID.preparation),
                        .send(.blocklists(.stop))
                    )
                case .refresh:
                    guard !state.busy else {
                        return .none
                    }
                    state.busy = true
                    return perform(.snapshot)
                case .prepareSnapshot(let snapshot):
                    return prepare(snapshot, state: &state)
                case .received(var snapshot, let content, let revision):
                    if let revision, revision !== state.content {
                        return prepare(snapshot, state: &state)
                    }
                    if content == nil {
                        snapshot = snapshot.normalizingConnectionIDs(previous: state.snapshot)
                        snapshot.rules = state.snapshot.rules.updating(with: snapshot.rules)
                    }
                    let selectedID: UUID?
                    let selectionEvent = state.selectionEvent
                    if state.rulesVisible {
                        selectedID = state.rules.indices.contains(state.selection)
                            ? state.rules[state.selection].id
                            : nil
                    } else {
                        selectedID = state.rows.indices.contains(state.selection) ? state.rows[state.selection].id : nil
                    }
                    if let content {
                        state.installContent(content)
                    } else {
                        state.snapshot = snapshot
                    }
                    if let catalog = snapshot.blocklists {
                        state.blocklists.catalog = state.blocklists.catalog.updating(with: catalog)
                    }
                    if let selected = state.selectedApplication,
                       !state.applications.contains(where: { $0.path == selected }) {
                        state.selectedApplication = nil
                    }
                    let tree = state.activityTree
                    if tree.nodes[state.home.selection] == nil {
                        state.home.selection = ActivityTree.all
                    }
                    state.home.expanded.formIntersection(tree.nodes.keys)
                    state.connected = true
                    state.busy = false
                    state.error = nil
                    let selection = min(state.selection, max(0, state.itemCount - 1))
                    if selection != state.selection {
                        state.selection = selection
                    }
                    if let selectedID {
                        let position = state.rulesVisible
                            ? state.rules.firstIndex { $0.id == selectedID }
                            : state.rows.firstIndex { $0.id == selectedID }
                        if let position {
                            if state.selection != position {
                                state.selection = position
                            }
                            // A refresh moves the same selected identity; it does
                            // not acknowledge a newer, still-pending cursor event.
                            state.selectionEvent = selectionEvent
                        }
                    }
                    if let detail = state.detail,
                       let updated = snapshot.rows.first(where: { $0.id == detail.id }) {
                        state.detail = updated
                    }
                    return .none
                case .tick(let date):
                    if state.connected {
                        state.activity.record(state.snapshot, at: date)
                    }
                    let missing = Set(state.snapshot.rows.map(\.address)).subtracting(state.locations.keys)
                    return missing.isEmpty ? .none : .send(.locate(Array(missing)))
                case .locate(let addresses):
                    return .run { send in
                        do {
                            await send(.located(try await Database.locate(addresses)))
                        } catch {
                            await send(.locationFailed(error.localizedDescription))
                        }
                    }
                    .cancellable(id: CancelID.locations, cancelInFlight: true)
                case .located(let locations):
                    var combined = state.locations.merging(locations) { _, new in new }
                    let retained = Set(state.snapshot.rows.map(\.address))
                    combined = combined.filter { retained.contains($0.key) }
                    if combined != state.locations {
                        state.locations = combined
                    }
                    state.locationError = nil
                    return .none
                case .locationFailed(let error):
                    state.locationError = error
                    return .none
                case .toggleMap:
                    state.page = .home
                    state.detail = nil
                    return .none
                case .toggleList:
                    state.page = state.page == .activity ? .home : .activity
                    state.detail = nil
                    state.selectedApplication = nil
                    state.selection = 0
                    return .none
                case .toggleGraph:
                    state.graphVisible.toggle()
                    return .none
                case .selectNode(let id, let event):
                    if id == ActivityTree.all {
                        state.home.selection = id
                        state.selectedApplication = nil
                        state.application = nil
                        state.selection = 0
                        state.selectionEvent = event
                        state.detail = nil
                    } else if state.node(id) != nil {
                        state.home.selection = id
                    }
                    state.home.selectionEvent = event
                    return .none
                case .activateNode(let id):
                    guard let node = state.node(id) else {
                        return .none
                    }
                    state.home.selection = id
                    if let connection = node.connection {
                        state.detail = connection
                    } else if node.hasChildren {
                        if !state.home.expanded.insert(id).inserted {
                            state.home.expanded.remove(id)
                        }
                    }
                    return .none
                case .toggleNode(let id):
                    guard state.node(id)?.hasChildren == true else {
                        return .none
                    }
                    state.home.selection = id
                    if !state.home.expanded.insert(id).inserted {
                        state.home.expanded.remove(id)
                    }
                    return .none
                case .expandNode(let id):
                    guard let node = state.node(id) else {
                        return .none
                    }
                    if node.hasChildren, state.home.expanded.insert(id).inserted {
                        return .none
                    }
                    if let child = node.children.first {
                        state.home.selection = child
                    }
                    return .none
                case .collapseNode(let id):
                    if state.home.expanded.remove(id) == nil,
                       let parent = state.node(id)?.parent {
                        state.home.selection = parent
                    }
                    return .none
                case .openConnection(let id):
                    state.detail = state.rows.first { $0.id == id }
                    return .none
                case .closeDetail:
                    state.detail = nil
                    return .none
                case .failed(let error):
                    state.error = error
                    state.busy = false
                    state.connected = false
                    return .none
                case .move(let delta):
                    state.selection = max(
                        0,
                        min(max(0, state.itemCount - 1), state.selection + delta)
                    )
                    return .none
                case .search(let query):
                    state.query = query
                    state.blocklists.query = query
                    state.selection = 0
                    // List's app/service scope is independent of its search text.
                    // Avoid rebuilding the entire navigation tree for every edit.
                    if state.page != .activity {
                        let tree = state.activityTree
                        if tree.nodes[state.home.selection] == nil {
                            state.home.selection = ActivityTree.all
                        }
                    }
                    return .none
                case .selectSearchField(let field):
                    state.searchField = field
                    state.selection = 0
                    return .none
                case .moveSearchField(let delta):
                    let fields = ConnectionQuery.Field.allCases
                    let index = fields.firstIndex(of: state.searchField) ?? 0
                    state.searchField = fields[((index + delta % fields.count) + fields.count) % fields.count]
                    state.selection = 0
                    return .none
                case .switchView:
                    state.page = state.rulesVisible ? .home : .rules
                    state.detail = nil
                    state.selection = 0
                    return .none
                case .show(let page):
                    state.page = page
                    state.detail = nil
                    state.selection = 0
                    state.selectedApplication = nil
                    return .none
                case .selectApplication(let path):
                    state.selectedApplication = path
                    state.selection = 0
                    return .none
                case .selectConnection(let id, let event):
                    let index = state.selectedApplication == nil
                        ? state.listFocus.positions[id]
                        : state.rows.firstIndex(where: { $0.id == id })
                    if let index {
                        state.selection = index
                        state.selectionEvent = event
                    }
                    return .none
                case .selectRule(let id, let event):
                    if let index = state.rules.firstIndex(where: { $0.id == id }) {
                        state.selection = index
                        state.selectionEvent = event
                    }
                    return .none
                case .blockDestination, .blockApp, .blockAppDestination:
                    if let connection = state.detail ?? state.commandConnection,
                       connection.direction != .outbound {
                        state.error = "Only outgoing connections use blocking rules. Incoming connections are observed."
                        return .none
                    }
                    if case .blockApp = action,
                       state.page == .home || state.page == .map,
                       !state.busy {
                        guard let scope = state.focusedNode?.scope else {
                            state.error = "Choose an application or executable service."
                            return .none
                        }
                        do {
                            state.busy = true
                            return perform(
                                .add(
                                    try Firewall.Rule(
                                        app: scope.path,
                                        applicationScope: scope.scope
                                    )
                                )
                            )
                        } catch {
                            state.busy = false
                            state.error = error.localizedDescription
                            return .none
                        }
                    }
                    if case .blockApp = action,
                       state.detail == nil,
                       !state.rulesVisible,
                       let app = state.selectedApplication,
                       !state.busy {
                        do {
                            state.busy = true
                            return perform(.add(try Firewall.Rule(app: app)))
                        } catch {
                            state.busy = false
                            state.error = error.localizedDescription
                            return .none
                        }
                    }
                    guard !state.rulesVisible,
                          let row = state.detail ?? state.commandConnection,
                          !state.busy else {
                        return .none
                    }
                    do {
                        let app = if case .blockDestination = action {
                            nil as String?
                        } else {
                            row.app
                        }
                        let domain = if case .blockApp = action {
                            nil as String?
                        } else {
                            row.destination
                        }
                        state.busy = true
                        return perform(.add(try Firewall.Rule(app: app, domain: domain)))
                    } catch {
                        state.error = error.localizedDescription
                        return .none
                    }
                case .toggleRule, .removeRule:
                    guard state.rulesVisible,
                          state.rules.indices.contains(state.selection),
                          !state.busy else {
                        return .none
                    }
                    let id = state.rules[state.selection].id
                    state.busy = true
                    return perform(action.isRemove ? .remove(id) : .toggle(id))
                case .addDomain(let domain):
                    guard !state.busy else {
                        return .none
                    }
                    do {
                        let rule = try Firewall.Rule(domain: domain)
                        state.busy = true
                        return perform(.add(rule))
                    } catch {
                        state.error = error.localizedDescription
                        return .none
                    }
                case .importDomains(let text):
                    guard !state.busy else {
                        return .none
                    }
                    state.busy = true
                    return perform(.importDomains(text))
                case .clearHistory:
                    guard !state.busy else {
                        return .none
                    }
                    state.busy = true
                    return perform(.clearHistory)
            }
        }
    }

    private func prepare(_ snapshot: Firewall.Snapshot, state: inout State) -> EffectOf<Self> {
        state.busy = true
        let preparation = Content.Preparation(snapshot: snapshot, state: state)
        return .run { send in
            let content = await preparation.content()
            guard !Task.isCancelled else {
                return
            }
            await send(.received(content.snapshot, content: content, revision: preparation.revision))
        }
        .cancellable(id: CancelID.preparation, cancelInFlight: true)
    }

    private func perform(_ request: Firewall.Request) -> EffectOf<Self> {
        .run { [client] send in
            do {
                await send(.prepareSnapshot(try await client.request(request)))
            } catch {
                await send(.failed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.request)
    }
}

extension MonitorFeature.Action {

    fileprivate var isRemove: Bool {
        if case .removeRule = self {
            true
        } else {
            false
        }
    }
}
