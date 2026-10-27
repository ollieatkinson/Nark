import Foundation

extension Firewall {

    /// An executable, or all executables contained in an application bundle.
    public struct Application: Codable, Hashable, Sendable {

        public enum Scope: String, Codable, Hashable, Sendable {
            case executable
            case bundle
        }

        public let path: String
        public let scope: Scope
        public init(path: String, scope: Scope) throws {
            guard path.hasPrefix("/"), path.utf8.count <= 4096 else {
                throw Firewall.Error.message("Specify an absolute application or executable path.")
            }
            let normalized = Self.normalized(path)
            guard normalized != "/", scope != .bundle || normalized.hasSuffix(".app") else {
                throw Firewall.Error.message("Application scope requires an .app bundle.")
            }
            self.path = normalized
            self.scope = scope
        }

        private static func normalized(_ path: String) -> String {
            let path = URL(fileURLWithPath: path).standardizedFileURL.path
            #if os(macOS)
                for prefix in ["/private/tmp", "/private/var", "/private/etc"] {
                    if
                        path == prefix || path
                            .hasPrefix(prefix + "/")
                    {
                        return String(path.dropFirst("/private".count))
                    }
                }
            #endif
            return path
        }

        public func validated() throws -> Self {
            try Self(path: path, scope: scope)
        }

        public func matches(_ executable: String) -> Bool {
            func contains(_ candidate: String) -> Bool {
                candidate == path || (scope == .bundle && candidate.hasPrefix(path + "/"))
            }
            if contains(executable) {
                return true
            }
            // Foundation may spell a target /tmp/... while Security returns /private/tmp/....
            return executable.hasPrefix("/") && contains(Self.normalized(executable))
        }
    }
}
