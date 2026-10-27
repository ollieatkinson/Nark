import Foundation

extension Firewall.Hostname.Inspection {

    /// One bounded handshake attempt. TCP callbacks may overlap previously peeked
    /// bytes; UDP callbacks are complete datagrams and use CRYPTO stream offsets.
    public struct Session: Sendable {

        public enum Transport: Sendable {
            case tcp
            case quic
        }

        private let transport: Transport
        private var prefix: [UInt8] = []
        private var quic = QUIC()
        public init(_ transport: Transport) {
            self.transport = transport
        }

        public mutating func inspect(_ data: Data, at offset: Int) -> Result {
            if transport == .quic {
                return quic.inspect(data)
            }
            guard offset >= 0, offset <= prefix.count, offset < limit else {
                return .unavailable
            }
            let bytes = Array(data.prefix(limit - offset))
            let overlap = min(prefix.count - offset, bytes.count)
            guard prefix[offset ..< (offset + overlap)].elementsEqual(bytes.prefix(overlap))
            else {
                return .unavailable
            }
            prefix += bytes.dropFirst(overlap)
            return Firewall.Hostname.Inspection.inspect(Data(prefix))
        }
    }
}
