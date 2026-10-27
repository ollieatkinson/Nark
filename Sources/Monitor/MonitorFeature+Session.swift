import ComposableArchitecture
import Control
import Firewall
import Foundation
import Vocabulary

extension MonitorFeature {

    /// Owns the message subscription for one terminal session.
    @MainActor public final class Session {

        public let store: StoreOf<MonitorFeature>
        public let events: Events
        private let observer: Events.Observer

        public init(client: Firewall.Client, application: Firewall.Application? = nil) {
            var state = State()
            state.application = application
            let store = Store(initialState: state) { MonitorFeature(client: client) }
            let events = Events()
            self.store = store
            self.events = events
            observer = events.on { [weak store] event in
                guard let action = Self.action(for: event) else {
                    return
                }
                _ = await MainActor.run { store?.send(action) }
            }
        }

        deinit {
            observer.cancel()
            events.finish()
        }

        nonisolated public static func action(for event: Event) -> Action? {
            switch event.detail.id {
                case nark.ux.monitor.home.tree.row.event.select:
                    guard let id = try? event[nark.ux.monitor.home.tree.row, as: String.self]
                    else {
                        return nil
                    }
                    return .selectNode(id)
                case nark.ux.monitor.home.tree.row.event.activate:
                    guard let id = try? event[nark.ux.monitor.home.tree.row, as: String.self]
                    else {
                        return nil
                    }
                    return .activateNode(id)
                case nark.ux.monitor.home.tree.row.disclosure.event.select:
                    guard let id = try? event[nark.ux.monitor.home.tree.row, as: String.self]
                    else {
                        return nil
                    }
                    return .toggleNode(id)
                case nark.ux.monitor.home.tree.row.event.expand:
                    guard let id = try? event[nark.ux.monitor.home.tree.row, as: String.self]
                    else {
                        return nil
                    }
                    return .expandNode(id)
                case nark.ux.monitor.home.tree.row.event.collapse:
                    guard let id = try? event[nark.ux.monitor.home.tree.row, as: String.self]
                    else {
                        return nil
                    }
                    return .collapseNode(id)
                case nark.ux.monitor.view.home.event.select:
                    return .show(.home)
                case nark.ux.monitor.view.list.event.select:
                    return .show(.activity)
                case nark.ux.monitor.view.list.toggle.event.select:
                    return .toggleList
                case nark.ux.monitor.view.graph.event.select:
                    return .toggleGraph
                case nark.ux.monitor.connections.event.move,
                     nark.ux.monitor.rules.event.move:
                    guard let delta: Int = try? event[type: Int.self] else {
                        return nil
                    }
                    return .move(delta)
                case nark.ux.monitor.search.event.change:
                    guard let query = try? event[nark.ux.monitor.search, as: String.self]
                    else {
                        return nil
                    }
                    return .search(query)
                case nark.ux.monitor.search.field.event.select:
                    guard
                        let raw = try? event[nark.ux.monitor.search.field, as: String.self],
                        let field = ConnectionQuery.Field(rawValue: raw)
                    else {
                        return nil
                    }
                    return .selectSearchField(field)
                case nark.ux.monitor.search.field.event.move:
                    guard let delta = try? event[nark.ux.monitor.search.field, as: Int.self]
                    else {
                        return nil
                    }
                    return .moveSearchField(delta)
                case nark.ux.monitor.blocklists.community.show.event.select:
                    return .blocklists(.showCommunity)
                case nark.ux.monitor.blocklists.community.category.event.select:
                    return .blocklists(.cycleCategory)
                case nark.ux.monitor.blocklists.community.add.event.select:
                    return .blocklists(.addSelectedCommunity)
                case nark.ux.monitor.blocklists.community.row.event.select:
                    guard let raw = try? event[
                        nark.ux.monitor.blocklists.community.row,
                        as: String.self
                    ], let id = UUID(uuidString: raw) else {
                        return nil
                    }
                    return .blocklists(.selectCommunity(id))
                case nark.ux.monitor.blocklists.community.row.event.activate:
                    guard let raw = try? event[
                        nark.ux.monitor.blocklists.community.row,
                        as: String.self
                    ], let id = UUID(uuidString: raw) else {
                        return nil
                    }
                    return .blocklists(.addCommunity(id))
                case nark.ux.monitor.blocklists.row.event.select:
                    guard
                        let raw = try? event[nark.ux.monitor.blocklists.row, as: String.self],
                        let id = UUID(uuidString: raw)
                    else {
                        return nil
                    }
                    return .blocklists(.select(id))
                case nark.ux.monitor.blocklists.row.event.activate:
                    guard
                        let raw = try? event[nark.ux.monitor.blocklists.row, as: String.self],
                        let id = UUID(uuidString: raw)
                    else {
                        return nil
                    }
                    return .blocklists(.open(id))
                case nark.ux.monitor.blocklists.toggle.event.select:
                    return .blocklists(.toggle)
                case nark.ux.monitor.blocklists.refresh.event.select:
                    return .blocklists(.refresh)
                case nark.ux.monitor.blocklists.remove.event.select:
                    return .blocklists(.remove)
                case nark.ux.monitor.blocklists.close.event.select:
                    return .blocklists(.close)
                case nark.ux.monitor.blocklists.import.event.select:
                    guard let source = try? event[
                        nark.ux.monitor.blocklists.import,
                        as: String.self
                    ] else {
                        return nil
                    }
                    return .blocklists(.importSource(source))
                case nark.ux.monitor.view.activity.event.select:
                    return .show(.activity)
                case nark.ux.monitor.view.rules.event.select:
                    return .show(.rules)
                case nark.ux.monitor.view.event.select:
                    return .switchView
                case nark.ux.monitor.applications.row.event.select:
                    guard let path = try? event[nark.ux.monitor.applications.row, as: String.self]
                    else {
                        return nil
                    }
                    return .selectApplication(path == "*" ? nil : path)
                case nark.ux.monitor.map.toggle.event.select:
                    return .toggleMap
                case nark.ux.monitor.detail.close.event.select:
                    return .closeDetail
                case nark.ux.monitor.connections.row.event.activate:
                    guard
                        let raw = try? event[nark.ux.monitor.connections.row, as: String.self],
                        let id = UUID(uuidString: raw)
                    else {
                        return nil
                    }
                    return .openConnection(id)
                case nark.ux.monitor.connections.row.event.select:
                    guard
                        let raw = try? event[nark.ux.monitor.connections.row, as: String.self],
                        let id = UUID(uuidString: raw)
                    else {
                        return nil
                    }
                    return .selectConnection(id)
                case nark.ux.monitor.rules.row.event.select:
                    guard
                        let raw = try? event[nark.ux.monitor.rules.row, as: String.self],
                        let id = UUID(uuidString: raw)
                    else {
                        return nil
                    }
                    return .selectRule(id)
                case nark.ux.monitor.block.destination.event.select:
                    return .blockDestination
                case nark.ux.monitor.block.application.event.select:
                    return .blockApp
                case nark.ux.monitor.block.connection.event.select:
                    return .blockAppDestination
                case nark.ux.monitor.rules.toggle.event.select:
                    return .toggleRule
                case nark.ux.monitor.rules.remove.event.select:
                    return .removeRule
                case nark.ux.monitor.rules.add.event.select:
                    guard let domain = try? event[nark.ux.monitor.rules.add, as: String.self]
                    else {
                        return nil
                    }
                    return .addDomain(domain)
                case nark.ux.monitor.rules.import.event.select:
                    guard let text = try? event[nark.ux.monitor.rules.import, as: String.self]
                    else {
                        return nil
                    }
                    return .importDomains(text)
                case nark.activity.clear:
                    return .clearHistory
                case nark.activity.refresh:
                    return .refresh
                default:
                    return nil
            }
        }
    }
}
