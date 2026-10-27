import Foundation

extension Firewall {

    public struct Connection: Codable, Hashable, Identifiable, Sendable {

        public var id: UUID
        public var app: String
        public var host: String?
        public var address: String
        public var port: String
        public var transport: String
        public var blocked: Bool
        public var count: Int
        public var lastSeen: Date
        public var traffic: Firewall.Traffic.Bytes?
        public var direction: Firewall.Direction
        public var localAddress: String?
        public var localPort: String?
        public var destination: String {
            host ?? address
        }

        public init(
            id: UUID = UUID(), app: String, host: String?, address: String, port: String,
            transport: String, blocked: Bool, count: Int = 1, lastSeen: Date = Date(),
            traffic: Firewall.Traffic.Bytes? = nil,
            direction: Firewall.Direction = .outbound, localAddress: String? = nil,
            localPort: String? = nil
        ) {
            self.id = id
            self.app = app
            self.host = host
            self.address = address
            self.port = port
            self.transport = transport
            self.blocked = blocked
            self.count = count
            self.lastSeen = lastSeen
            self.traffic = traffic
            self.direction = direction
            self.localAddress = localAddress
            self.localPort = localPort
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case app
            case host
            case address
            case port
            case transport
            case blocked
            case count
            case lastSeen
            case traffic
            case direction
            case localAddress
            case localPort
        }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(UUID.self, forKey: .id)
            app = try values.decode(String.self, forKey: .app)
            host = try values.decodeIfPresent(String.self, forKey: .host)
            address = try values.decode(String.self, forKey: .address)
            port = try values.decode(String.self, forKey: .port)
            transport = try values.decode(String.self, forKey: .transport)
            blocked = try values.decode(Bool.self, forKey: .blocked)
            count = try values.decode(Int.self, forKey: .count)
            lastSeen = try values.decode(Date.self, forKey: .lastSeen)
            traffic = try values.decodeIfPresent(Firewall.Traffic.Bytes.self, forKey: .traffic)
            // Earlier providers recorded only outgoing connections.
            direction = try values
                .decodeIfPresent(Firewall.Direction.self, forKey: .direction) ?? .outbound
            localAddress = try values.decodeIfPresent(String.self, forKey: .localAddress)
            localPort = try values.decodeIfPresent(String.self, forKey: .localPort)
        }
    }
}

extension Firewall.Connection {

    func sharesDestination(with other: Self) -> Bool {
        app == other.app && host == other.host && address == other.address
            && port == other.port && transport == other.transport && blocked == other.blocked
            && direction == other.direction
            &&
            (direction != .inbound ||
                (localAddress == other.localAddress && localPort == other.localPort))
    }
}
