import Foundation

extension Firewall {

    public struct Rule: Codable, Hashable, Identifiable, Sendable {

        public var id: UUID
        public var app: String?
        public var domain: String?
        public var enabled: Bool
        public var applicationScope: Firewall.Application.Scope?
        public init(
            id: UUID = UUID(),
            app: String? = nil,
            domain: String? = nil,
            enabled: Bool = true,
            applicationScope: Firewall.Application.Scope? = nil
        ) throws {
            guard app != nil || domain != nil else {
                throw Firewall.Error.message("Specify an app path or domain.")
            }
            if let app, !app.hasPrefix("/") {
                throw Firewall.Error.message("App must be an absolute executable path.")
            }
            if let domain, Firewall.Hostname.normalize(domain) == nil {
                throw Firewall.Error.message("Invalid domain or IP: \(domain)")
            }
            self.id = id
            if let applicationScope {
                guard let app else {
                    throw Firewall.Error.message("An application scope requires a path.")
                }
                _ = try Firewall.Application(path: app, scope: applicationScope)
            }
            self.app = app
            self.domain = domain.flatMap(Firewall.Hostname.normalize)
            self.enabled = enabled
            self.applicationScope = applicationScope
        }

        public func matches(
            app: String,
            host: String?,
            address: String,
            direction: Firewall.Direction = .outbound
        ) -> Bool {
            guard enabled, direction == .outbound else {
                return false
            }
            if let own = self.app {
                if applicationScope == .bundle {
                    guard (try? Firewall.Application(path: own, scope: .bundle).matches(app)) == true else {
                        return false
                    }
                } else if own != app {
                    return false
                }
            }
            guard let domain else {
                return true
            }
            return Firewall.Hostname.matches(host ?? "", domain: domain)
                || Firewall.Hostname.matches(address, domain: domain)
        }

        public func validated() throws -> Self {
            try Self(
                id: id,
                app: app,
                domain: domain,
                enabled: enabled,
                applicationScope: applicationScope
            )
        }
    }
}
