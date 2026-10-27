extension Firewall {

    /// The initiator of a connection, independent of its upload/download traffic.
    public enum Direction: String, Codable, Hashable, Sendable {
        case inbound
        case outbound
        case unknown
        public var name: String {
            switch self {
                case .inbound:
                    "Incoming"
                case .outbound:
                    "Outgoing"
                case .unknown:
                    "Unknown direction"
            }
        }
    }
}
