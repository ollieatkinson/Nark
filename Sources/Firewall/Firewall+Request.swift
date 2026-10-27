import Foundation

extension Firewall {

    public enum Request: Codable, Sendable {
        case blocklist(Firewall.Blocklist.Request)
        case recording(Firewall.Recording.Request)
        case snapshot
        case add(Firewall.Rule)
        case remove(UUID)
        case toggle(UUID)
        case importDomains(String)
        case clearHistory
    }
}
