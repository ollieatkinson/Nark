import ComposableArchitecture
import Control
import Firewall
import Foundation

@Reducer public struct BlocklistsFeature {

    @ObservableState public struct State: Equatable {

        public var catalog = Firewall.Blocklist.presets.map(\.summary)
        public var selection: UUID? = Firewall.Blocklist.presets.first?.id {
            didSet { selectionEvent = nil }
        }

        public var selectionEvent: UInt?
        public var detail: Firewall.Blocklist?
        public var query = ""
        public var communityVisible = false
        public var communitySelection = Firewall.Blocklist.community[0].id {
            didSet { communitySelectionEvent = nil }
        }

        public var communitySelectionEvent: UInt?
        public var category: Firewall.Blocklist.Category?
        public var busy = false
        public var error: String?
        public init() {}
        public var community: [Firewall.Blocklist.Community] {
            Firewall.Blocklist.community.filter {
                (category.map($0.categories.contains) ?? true)
                    && (query.isEmpty || "\($0.name) \($0.description)".localizedCaseInsensitiveContains(query))
            }
        }

        public var selectedCommunity: Firewall.Blocklist.Community? {
            community.first { $0.id == communitySelection } ?? community.first
        }

        public var selected: Firewall.Blocklist.Summary? {
            catalog.first { $0.id == selection }
        }

        public var domains: [String] {
            guard let detail else {
                return []
            }
            guard !query.isEmpty else {
                return detail.domains
            }
            let needle = query.lowercased()
            return detail.domains.filter { $0.contains(needle) }
        }
    }

    public enum Action: Sendable {
        case select(UUID, event: UInt? = nil)
        case open(UUID)
        case close
        case showCommunity
        case cycleCategory
        case selectCommunity(UUID, event: UInt? = nil)
        case addCommunity(UUID)
        case addSelectedCommunity
        case toggle
        case refresh
        case remove
        case importSource(String)
        case fetched(Firewall.Blocklist.Import)
        case saved([Firewall.Blocklist.Summary], selected: UUID?)
        case loaded(Firewall.Blocklist)
        case failed(String)
        case stop
    }

    public let client: Firewall.Client
    private let load: @Sendable (String) async throws -> Firewall.Blocklist.Import
    public init(
        client: Firewall.Client,
        load: @escaping @Sendable (String) async throws -> Firewall.Blocklist.Import = BlocklistSource.read
    ) {
        self.client = client
        self.load = load
    }

    private enum CancelID {
        case operation
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .select(let id, let event):
                    state.selection = id
                    state.selectionEvent = event
                    return .none
                case .close:
                    state.detail = nil
                    state.communityVisible = false
                    return .none
                case .showCommunity:
                    state.communityVisible = true
                    state.detail = nil
                    state.error = nil
                    return .none
                case .selectCommunity(let id, let event):
                    state.communitySelection = id
                    state.communitySelectionEvent = event
                    return .none
                case .cycleCategory:
                    let choices: [Firewall.Blocklist.Category?] = [nil] + Firewall.Blocklist.Category.allCases.map {
                        Optional($0)
                    }
                    state.category = choices[((choices.firstIndex(of: state.category) ?? 0) + 1) % choices.count]
                    if !state.community.contains(where: { $0.id == state.communitySelection }) {
                        state.communitySelection = state.community.first?.id ?? state.communitySelection
                    }
                    return .none
                case .addSelectedCommunity:
                    guard let selected = state.selectedCommunity else {
                        return .none
                    }
                    return .send(.addCommunity(selected.id))
                case .addCommunity(let id):
                    guard !state.busy,
                          let selected = Firewall.Blocklist.community.first(where: { $0.id == id }) else {
                        return .none
                    }
                    if state.catalog.contains(where: { $0.id == id }) {
                        state.selection = id
                        state.communityVisible = false
                        return .none
                    }
                    state.busy = true
                    state.error = nil
                    return fetch(selected.source, id: id, enable: false)
                case .stop:
                    return .cancel(id: CancelID.operation)
                case .open(let id):
                    guard !state.busy else {
                        return .none
                    }
                    state.selection = id
                    state.busy = true
                    state.error = nil
                    return .run { [client] send in
                        do {
                            await send(.loaded(try await client.blocklist(id)))
                        } catch {
                            await send(.failed(error.localizedDescription))
                        }
                    }
                    .cancellable(id: CancelID.operation)
                case .loaded(let list):
                    state.detail = list
                    state.busy = false
                    return .none
                case .toggle, .refresh:
                    guard !state.busy, let selected = state.selected else {
                        return .none
                    }
                    state.busy = true
                    state.error = nil
                    if case .toggle = action,
                       selected.domainCount > 0 {
                        return mutate(.toggle(selected.id))
                    }
                    return fetch(
                        selected.source,
                        id: selected.id,
                        enable: action.isToggle ? true : nil
                    )
                case .remove:
                    guard !state.busy, let selected = state.selected else {
                        return .none
                    }
                    state.busy = true
                    state.error = nil
                    return mutate(.remove(selected.id))
                case .importSource(let source):
                    guard !state.busy else {
                        return .none
                    }
                    state.busy = true
                    state.error = nil
                    return fetch(source, id: nil, enable: nil)
                case .fetched(let input):
                    return mutate(.replace(input), selectSource: input.source)
                case .saved(let catalog, let selected):
                    state.catalog = state.catalog.updating(with: catalog)
                    state.busy = false
                    if let selected {
                        state.selection = selected
                        state.communityVisible = false
                    }
                    if !catalog.contains(where: { $0.id == state.selection }) {
                        state.selection = catalog.first?.id
                    }
                    if let detail = state.detail,
                       let summary = catalog.first(where: { $0.id == detail.id }) {
                        state.detail?.summary = summary
                        if detail.summary.updatedAt != summary.updatedAt {
                            return .send(.open(detail.id))
                        }
                    } else {
                        state.detail = nil
                    }
                    return .none
                case .failed(let error):
                    state.error = error
                    state.busy = false
                    return .none
            }
        }
    }

    private func fetch(_ source: String, id: UUID?, enable: Bool?) -> EffectOf<Self> {
        .run { [load] send in
            do {
                var input = try await load(source)
                input.id = id ?? input.id
                input.enable = enable
                await send(.fetched(input))
            } catch {
                await send(.failed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.operation, cancelInFlight: true)
    }

    private func mutate(
        _ request: Firewall.Blocklist.Request,
        selectSource: String? = nil
    ) -> EffectOf<Self> {
        .run { [client] send in
            do {
                let catalog = try await client.request(.blocklist(request)).blocklists ?? []
                let selected = selectSource.flatMap { source in catalog.first { $0.source == source }?.id }
                await send(.saved(catalog, selected: selected))
            } catch {
                await send(.failed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.operation)
    }
}

private extension BlocklistsFeature.Action {

    var isToggle: Bool {
        if case .toggle = self {
            true
        } else {
            false
        }
    }
}
