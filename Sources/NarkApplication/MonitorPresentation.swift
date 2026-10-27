import Firewall
import Foundation
import Monitor
import NarkUI

/// Presentation decisions shared by the monitor's composed views.
extension MonitorFeature.State {

    var trafficTrackingSummary: String {
        let untracked = snapshot.traffic?.untrackedFlows ?? 0
        if untracked > 0 {
            return "\(untracked) flows outside byte tracking"
        }
        let rules = snapshot.rules.filter(\.enabled).count
        let lists = blocklists.catalog.filter(\.enabled).count
        return "\(rules) rules · \(lists) lists on"
    }

    var navigationHint: String {
        if let detail {
            if detail.direction == .outbound {
                return "h home · esc back · b block site · a block app · x block app+site"
            }
            return "h home · esc back · incoming connections are observed and allowed"
        }
        switch page {
            case .home, .map:
                return "esc all apps · ←/→ fold · l full list · / search · r rules"
            case .activity:
                return "u all apps · f field · / filter · c clear · h/esc home · g graph"
            case .rules:
                return "h/esc home · p community lists · i paste URL/file · / search"
        }
    }

    var searchTitle: String {
        if rulesVisible {
            return "Search"
        }
        return "Search \(searchField.title)"
    }

    var searchHint: String {
        if query.isEmpty {
            if rulesVisible {
                return "tab pane · space on/off · enter inspect list · u refresh · d delete"
            }
            return "a block app · x block app+site"
        }
        let clearKey = page == .activity ? "c" : "esc"
        return "\(searchTitle): \(query.formatted(.terminalText)) · \(clearKey) clear"
    }

    var emptyRulesMessage: String {
        if query.isEmpty {
            return "No manual rules. Press n to block a domain."
        }
        return "No rules match this search."
    }

    var rulesNeedKeyboardFocus: Bool {
        guard rulesVisible else {
            return false
        }
        let emptyCommunity = blocklists.communityVisible && (blocklists.community.isEmpty || blocklists.busy)
        let emptyDomains = blocklists.detail?.domains.isEmpty == true
        let emptyCatalog = rules.isEmpty && blocklists.catalog.isEmpty
        return emptyCommunity || emptyDomains || emptyCatalog
    }

    static func connectionListHint(count: Int) -> String {
        if count == 0 {
            return "No matches · u all apps · / edit filter · c clear"
        }
        return "\(count) records · u all apps · / filter · c clear"
    }
}

extension BlocklistsFeature.State {

    var communityHint: String {
        if busy {
            return "Downloading and validating…"
        }
        return "Feeds are maintained by their publishers. Import another HTTPS URL with i."
    }

    var catalogHint: String {
        if busy {
            return "Updating blocklist…"
        }
        return "p community lists · i paste URL/file"
    }
}

extension Firewall.Snapshot {

    func policyDescription(for connection: Firewall.Connection) -> String {
        guard connection.direction == .outbound else {
            return "ALLOW · observation only"
        }
        guard blocks(connection) else {
            return "ALLOW · no matching enabled rule"
        }
        let matches = rules.filter {
            $0.matches(
                app: connection.app,
                host: connection.host,
                address: connection.address,
                direction: connection.direction
            )
        }
        if matches.isEmpty {
            return "BLOCK · enabled blocklist"
        }
        return "BLOCK · \(matches.count) matching rule(s)"
    }
}
