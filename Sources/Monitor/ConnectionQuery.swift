import Firewall
import Foundation

/// A parsed activity filter, shared by Home and List. Parsing happens once per
/// projection, rather than once per connection; policy lookup is lazy.
public struct ConnectionQuery: Equatable, Sendable {

    public enum Field: String, CaseIterable, Equatable, Sendable {
        case all
        case app
        case service
        case remote
        case local
        case port
        case type
        case dir
        case policy
        public var title: String {
            rawValue
        }

        static func named(_ name: String) -> Self? {
            switch name.lowercased() {
                case "application":
                    .app
                case "process":
                    .service
                case "host", "domain", "address", "ip":
                    .remote
                case "transport", "protocol":
                    .type
                case "direction":
                    .dir
                default:
                    Self(rawValue: name.lowercased())
            }
        }
    }

    private struct Term: Equatable, Sendable {

        let field: Field
        let value: String
    }

    private let terms: [Term]
    public init(_ text: String, field: Field = .all) {
        // Preserve bare direction shortcuts, while remote:incoming.mail remains a name.
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if field != .all {
            terms = value.isEmpty ? [] : [.init(field: field, value: value)]
            return
        }
        if ["incoming", "inbound", "↙", "outgoing", "outbound", "↗"].contains(value.lowercased()) {
            terms = [.init(field: .dir, value: value)]
            return
        }
        terms = Self.tokens(value).map { token in
            if let colon = token.firstIndex(of: ":"),
               let field = Field.named(String(token[..<colon])) {
                return Term(field: field, value: String(token[token.index(after: colon)...]))
            }
            return Term(field: .all, value: token)
        }
    }

    public func matches(_ row: Firewall.Connection, isBlocked: () -> Bool) -> Bool {
        terms.allSatisfy { term in
            if term.value.isEmpty {
                return true
            }
            let candidate: String
            switch term.field {
                case .all:
                    candidate = "\(row.app) \(row.destination) \(row.address) \(row.port) \(row.transport) \(row.direction.rawValue) \(row.direction.name)"
                case .app:
                    let parts = row.app.split(separator: "/")
                    candidate = parts.first(where: { $0.lowercased().hasSuffix(".app") })
                        .map(String.init)
                        ?? parts.last.map(String.init) ?? row.app
                case .service:
                    candidate = term.value.contains("/")
                        ? row.app
                        : row.app.split(separator: "/").last.map(String.init) ?? row.app
                case .remote:
                    candidate = "\(row.destination) \(row.address)"
                case .local:
                    candidate = "\(row.localAddress ?? "") \(row.localPort ?? "")"
                case .port:
                    candidate = row.port
                case .type:
                    candidate = row.transport
                case .dir:
                    candidate = "\(row.direction.rawValue) \(row.direction.name) \(row.direction == .inbound ? "incoming inbound ↙" : row.direction == .outbound ? "outgoing outbound ↗" : "unknown")"
                case .policy:
                    candidate = isBlocked() ? "block blocked" : "allow allowed"
            }
            return candidate.localizedCaseInsensitiveContains(term.value)
        }
    }

    private static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            if character == "\"" {
                quoted.toggle()
            } else if character.isWhitespace && !quoted {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
