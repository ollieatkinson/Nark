import Foundation

extension Firewall {

    public struct Blocklist: Codable, Equatable, Identifiable, Sendable {

        public struct Summary: Codable, Equatable, Identifiable, Sendable {

            public var id: UUID
            public var name: String
            public var source: String
            public var attribution: String
            public var enabled: Bool
            public var domainCount: Int
            public var updatedAt: Date?
        }

        public struct Import: Codable, Hashable, Sendable {

            public var id: UUID?
            public var name: String
            public var source: String
            public var attribution: String
            public var text: String
            public var enable: Bool?
            public init(
                id: UUID? = nil,
                name: String,
                source: String,
                attribution: String = "User supplied",
                text: String,
                enable: Bool? = nil
            ) {
                self.id = id
                self.name = name
                self.source = source
                self.attribution = attribution
                self.text = text
                self.enable = enable
            }
        }

        public enum Request: Codable, Sendable {
            case replace(Import)
            case toggle(UUID)
            case remove(UUID)
            case read(UUID)
        }

        public var summary: Summary
        public var domains: [String]
        public var id: UUID {
            summary.id
        }

        public static var presets: [Self] {
            community.prefix(2).map(\.template)
        }

        public func validated() throws -> Self {
            guard
                !summary.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !summary.source.isEmpty, summary.name.utf8.count <= 120,
                summary.source.utf8.count <= 4096,
                summary.attribution.utf8.count <= 1024, domains.count <= 500_000,
                !summary.enabled || !domains.isEmpty
            else {
                throw Firewall.Error.message("Invalid blocklist metadata.")
            }
            let domains = try domains.map { value -> String in
                guard
                    let normalized = Hostname.normalize(value),
                    normalized == value
                else {
                    throw Firewall.Error.message("Invalid blocklist domain.")
                }
                return normalized
            }
            var result = self
            result.domains = Array(Set(domains)).sorted()
            result.summary.domainCount = result.domains.count
            return result
        }
    }

    struct BlocklistStore: Sendable {

        var lists: [Blocklist]
        private var index: [(id: UUID, domains: Set<String>)] = []
        let url: URL?
        init(directory: URL?) throws {
            url = directory?.appendingPathComponent("blocklists.json")
            if let url, FileManager.default.fileExists(atPath: url.path) {
                lists = try JSONDecoder()
                    .decode([Blocklist].self, from: Data(contentsOf: url))
                    .map { try $0.validated() }
                guard
                    lists.count <= 32, lists.reduce(0, { $0 + $1.domains.count }) <= 1_000_000,
                    Set(lists.map(\.id)).count == lists.count
                else {
                    throw Firewall.Error.message("Invalid blocklist catalog.")
                }
            } else {
                lists = Blocklist.presets
            }
            rebuild()
        }

        mutating func apply(_ request: Blocklist.Request) throws {
            var updated = lists
            switch request {
                case .read:
                    return
                case .replace(let input):
                    guard input.text.utf8.count <= 8_000_000
                    else {
                        throw Firewall.Error.message("Blocklist exceeds 8 MB.")
                    }
                    let domains = try Runtime.parseBlocklist(input.text, limit: 8_000_000)
                    guard !domains.isEmpty
                    else {
                        throw Firewall.Error
                            .message(
                                "Blocklist contains no domains; the previous version was retained."
                            )
                    }
                    let existing = updated
                        .first { $0.id == input.id || $0.summary.source == input.source }
                    let list = try Blocklist(
                        summary: .init(
                            id: existing?.id ?? input.id ?? UUID(),
                            name: input.name,
                            source: input.source,
                            attribution: input.attribution,
                            enabled: input.enable ?? existing?
                                .summary.enabled ?? false,
                            domainCount: domains.count,
                            updatedAt: Date()
                        ),
                        domains: domains
                    ).validated()
                    if
                        let position = updated
                            .firstIndex(where: { $0.id == list.id })
                    {
                        updated[position] = list
                    } else {
                        updated.append(list)
                    }
                case .toggle(let id):
                    guard
                        let position = updated.firstIndex(where: { $0.id == id }),
                        !updated[position].domains.isEmpty
                    else {
                        throw Firewall.Error
                            .message("Download or import this blocklist before enabling it.")
                    }
                    updated[position].summary.enabled.toggle()
                case .remove(let id):
                    updated.removeAll { $0.id == id }
            }
            guard
                updated.count <= 32,
                updated.reduce(0, { $0 + $1.domains.count }) <= 1_000_000
            else {
                throw Firewall.Error
                    .message("Blocklist capacity exceeded (32 lists / 1,000,000 domains).")
            }
            if let url {
                try JSONEncoder().encode(updated).write(to: url, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: url.path
                )
            }
            lists = updated
            rebuild()
        }

        private mutating func rebuild() {
            index = lists.filter(\.summary.enabled).map { ($0.id, Set($0.domains)) }
        }

        func match(host: String?, address: String) -> UUID? {
            for list in index {
                for value in [host, address].compactMap({ $0 }).compactMap(Hostname.normalize) {
                    if list.domains.contains(value) {
                        return list.id
                    }
                    // IP literals match exactly. Hostnames include DNS-label-bounded subdomains.
                    if value.contains(":") {
                        continue
                    }
                    let labels = value.split(separator: ".")
                    if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
                        continue
                    }
                    for suffix in 1 ..< labels.count
                        where list.domains
                        .contains(labels.dropFirst(suffix).joined(separator: "."))
                    {
                        return list.id
                    }
                }
            }
            return nil
        }
    }
}
