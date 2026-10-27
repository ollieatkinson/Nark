import Foundation
import Monitor
import NarkUI
import SwiftTUI
import Vocabulary

/// Semantic intents and I/O for this experience; the dashboard only composes views.
@MainActor struct MonitorCommands {

    enum Prompt {
        case search
        case domain
        case file
        var title: String {
            switch self {
                case .search:
                    "Search"
                case .domain:
                    "Block domain or IP"
                case .file:
                    "Blocklist HTTPS URL or file"
            }
        }

        var hint: String {
            switch self {
                case .search:
                    "type to filter · enter done · esc cancel"
                case .domain, .file:
                    "enter confirm · esc cancel"
            }
        }
    }

    let session: MonitorFeature.Session
    var send: UI.EventAction {
        UI.EventAction(
            events: session.events
        ) { [session] in
            session.store.send(.failed($0.localizedDescription))
        }
    }

    func handle(_ key: KeyEvent) -> Bool {
        let event: Event
        switch key {
            case .character("u") where session.store.page == .activity:
                event = UI.Control(nark.ux.monitor.home.tree.row[ActivityTree.all]).select
            case .character("f") where session.store.page == .activity:
                event = Event(nark.ux.monitor.search.field[1].event.move)
            case .character("c") where session.store.page == .activity:
                event = UI.Control(nark.ux.monitor.search).changing("")
            case .character("h"):
                event = UI.Control(nark.ux.monitor.view.home).select
            case .character("p"):
                event = UI.Control(nark.ux.monitor.blocklists.community.show).select
            case .character("l"):
                event = UI.Control(nark.ux.monitor.view.list.toggle).select
            case .character("g"):
                event = UI.Control(nark.ux.monitor.view.graph).select
            case .character("m"):
                event = UI.Control(nark.ux.monitor.map.toggle).select
            case .character("r"):
                event = UI.Control(nark.ux.monitor.view).select
            case .character("b"):
                event = UI.Control(nark.ux.monitor.block.destination).select
            case .character("a"):
                event = UI.Control(nark.ux.monitor.block.application).select
            case .character("x"):
                event = UI.Control(nark.ux.monitor.block.connection).select
            case .escape:
                if session.store.rulesVisible
                    && (session.store.blocklists.detail != nil || session.store.blocklists.communityVisible) {
                    event = UI.Control(nark.ux.monitor.blocklists.close).select
                } else if session.store.detail != nil {
                    event = UI.Control(nark.ux.monitor.detail.close).select
                } else if session.store.page == .activity || session.store.rulesVisible {
                    event = UI.Control(nark.ux.monitor.view.home).select
                } else {
                    send(UI.Control(nark.ux.monitor.search).changing(""))
                    event = UI.Control(nark.ux.monitor.home.tree.row[ActivityTree.all]).select
                }
            default:
                return false
        }
        send(event)
        return true
    }

    func submit(_ prompt: Prompt, text: String) {
        switch prompt {
            case .search:
                break // UI.TextField has already published each edit.
            case .domain:
                send(UI.Control(nark.ux.monitor.rules.add[text]).select)
            case .file:
                send(UI.Control(nark.ux.monitor.blocklists.import[text]).select)
        }
    }

    func treeKey(_ key: KeyPress, selection: String? = nil) -> KeyPressResult {
        guard key.modifiers.isEmpty else {
            return .ignored
        }
        let row = nark.ux.monitor.home.tree.row[selection ?? session.store.home.selection]
        switch key.key {
            case .arrowRight:
                send(Event(row.event.expand))
            case .arrowLeft:
                send(Event(row.event.collapse))
            case .space:
                send(Event(row.disclosure.event.select))
            default:
                return .ignored
        }
        return .handled
    }

    func ruleKey(_ key: KeyPress) -> KeyPressResult {
        guard key.modifiers.isEmpty else {
            return .ignored
        }
        switch key.key {
            case .space:
                send(UI.Control(nark.ux.monitor.rules.toggle).select)
            case .character("d"):
                send(UI.Control(nark.ux.monitor.rules.remove).select)
            default:
                return .ignored
        }
        return .handled
    }

    func communityKey(_ key: KeyPress) -> KeyPressResult {
        guard key.modifiers.isEmpty else {
            return .ignored
        }
        if key.key == .character("c") {
            send(UI.Control(nark.ux.monitor.blocklists.community.category).select)
            return .handled
        }
        return .ignored
    }

    func blocklistKey(_ key: KeyPress) -> KeyPressResult {
        guard key.modifiers.isEmpty else {
            return .ignored
        }
        switch key.key {
            case .space:
                send(UI.Control(nark.ux.monitor.blocklists.toggle).select)
            case .character("u"):
                send(UI.Control(nark.ux.monitor.blocklists.refresh).select)
            case .character("d"):
                send(UI.Control(nark.ux.monitor.blocklists.remove).select)
            default:
                return .ignored
        }
        return .handled
    }
}
