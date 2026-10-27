import Foundation

extension Firewall.Blocklist {

    public enum Category: String, CaseIterable, Sendable {
        case advertising = "Advertising"
        case tracking = "Tracking"
        case security = "Security"
        case explicit = "Explicit"
        public var shortTitle: String {
            self == .advertising ? "Ads" : rawValue
        }
    }

    public struct Community: Identifiable, Equatable, Sendable {

        public let id: UUID
        public let name: String
        public let source: String
        public let attribution: String
        public let categories: [Category]
        public let description: String
        public var template: Firewall.Blocklist {
            .init(
                summary: .init(
                    id: id,
                    name: name,
                    source: source,
                    attribution: attribution,
                    enabled: false,
                    domainCount: 0
                ),
                domains: []
            )
        }
    }

    public static let community: [Community] = [
        .init(
            id: UUID(uuidString: "ADAA0000-0000-4000-8000-000000000001")!,
            name: "AdAway",
            source: "https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt",
            attribution: "AdAway: Kicelo, Dominik Schuermann & contributors · CC BY 3.0 · creativecommons.org/licenses/by/3.0/",
            categories: [.advertising, .tracking],
            description: "Mobile advertising and analytics domains maintained by the AdAway community."
        ),
        .init(
            id: UUID(uuidString: "A0A00000-0000-4000-8000-000000000002")!,
            name: "Peter Lowe",
            source: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=plain&mimetype=plaintext",
            attribution: "Peter Lowe · pgl.yoyo.org/adservers",
            categories: [
                .advertising,
                .tracking
            ],
            description: "A focused list of advertising and tracking hostnames."
        ),
        .init(
            id: UUID(uuidString: "A0A00000-0000-4000-8000-000000000003")!,
            name: "1Hosts Lite",
            source: "https://raw.githubusercontent.com/badmojr/1Hosts/master/Lite/adblock.txt",
            attribution: "1Hosts / badmojr · MPL 2.0 · github.com/badmojr/1Hosts",
            categories: [
                .advertising,
                .tracking,
                .security
            ],
            description: "The Lite variant of 1Hosts, covering advertising, trackers and malicious domains."
        ),
        .init(
            id: UUID(uuidString: "A0A00000-0000-4000-8000-000000000004")!,
            name: "OISD Small",
            source: "https://small.oisd.nl/",
            attribution: "OISD / Stephan van Ruth · GPL 3.0 · oisd.nl · github.com/sjhgvr/oisd/blob/main/LICENSE",
            categories: [.advertising, .tracking],
            description: "A compact OISD variant. Anchored domain rules also cover subdomains."
        ),
        .init(
            id: UUID(uuidString: "A0A00000-0000-4000-8000-000000000005")!,
            name: "Anudeep",
            source: "https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt",
            attribution: "Anudeep ND & contributors · MIT · github.com/anudeepND/blacklist",
            categories: [
                .advertising,
                .tracking,
                .security
            ],
            description: "A curated hosts list covering ads, tracking, malware and other unsafe domains."
        ),
        .init(
            id: UUID(uuidString: "A0A00000-0000-4000-8000-000000000006")!,
            name: "OISD NSFW Small",
            source: "https://nsfw-small.oisd.nl/",
            attribution: "OISD / Stephan van Ruth · GPL 3.0 · oisd.nl · github.com/sjhgvr/oisd/blob/main/LICENSE",
            categories: [.explicit],
            description: "Optional explicit-content blocking, limited to popular domains to keep the list compact."
        )
    ]
}
