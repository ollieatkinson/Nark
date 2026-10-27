import Foundation

/// Bounded, read-only inspection of TLS ClientHello SNI and plain HTTP Firewall.Hostname.
/// Reads visible handshake metadata only; encrypted ECH names remain unavailable.
extension Firewall.Hostname {

    public enum Inspection {

        public enum Result: Equatable, Sendable {
            case hostname(String)
            case needMore
            case unavailable
        }

        public static let limit = 16_384
        public static func inspect(_ data: Data) -> Result {
            let bytes = Array(data.prefix(limit))
            guard !bytes.isEmpty else {
                return .needMore
            }
            let result: Result
            if bytes[0] == 22 {
                result = tls(bytes)
            } else {
                result = http(bytes)
            }
            return result == .needMore && data.count >= limit ? .unavailable : result
        }

        private static func tls(_ b: [UInt8]) -> Result {
            // Reassemble the first handshake across TLS records without trusting lengths.
            var handshake: [UInt8] = []
            var position = 0
            while position < b.count {
                guard position + 5 <= b.count else {
                    return .needMore
                }
                guard b[position] == 22, b[position + 1] == 3 else {
                    return .unavailable
                }
                let length = u16(b, position + 3)
                guard length > 0, length <= limit - 5 else {
                    return .unavailable
                }
                guard position + 5 + length <= b.count else {
                    return .needMore
                }
                handshake += b[(position + 5) ..< (position + 5 + length)]
                position += 5 + length
                if handshake.count >= 4 {
                    guard handshake[0] == 1 else {
                        return .unavailable
                    }
                    let size = Int(handshake[1]) << 16 | Int(handshake[2]) << 8 | Int(handshake[3])
                    guard size <= limit - 4 else {
                        return .unavailable
                    }
                    if handshake.count >= size + 4 {
                        return clientHello(Array(handshake.prefix(size + 4)))
                    }
                }
            }
            return .needMore
        }

        static func clientHello(_ b: [UInt8]) -> Result {
            guard b.count >= 4, b[0] == 1 else {
                return .unavailable
            }
            let size = Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            guard size <= limit - 4 else {
                return .unavailable
            }
            guard b.count >= size + 4 else {
                return .needMore
            }
            guard b.count >= 39 else {
                return .unavailable
            }
            var p = 38
            let sessionLength = Int(b[p])
            p += 1 + sessionLength
            guard p + 2 <= b.count else {
                return .unavailable
            }
            let cipherLength = u16(b, p)
            p += 2 + cipherLength
            guard p < b.count else {
                return .unavailable
            }
            let compressionLength = Int(b[p])
            p += 1 + compressionLength
            guard p + 2 <= b.count else {
                return .unavailable
            }
            let end = p + 2 + u16(b, p)
            p += 2
            guard end <= b.count else {
                return .unavailable
            }
            while p + 4 <= end {
                let kind = u16(b, p)
                let length = u16(b, p + 2)
                p += 4
                guard p + length <= end else {
                    return .unavailable
                }
                if kind == 0 {
                    guard length >= 5, u16(b, p) == length - 2 else {
                        return .unavailable
                    }
                    var n = p + 2
                    while n + 3 <= p + length {
                        let type = b[n]
                        let size = u16(b, n + 1)
                        n += 3
                        guard n + size <= p + length else {
                            return .unavailable
                        }
                        if type == 0,
                           let raw = String(bytes: b[n ..< (n + size)], encoding: .utf8),
                           let host = Firewall.Hostname.normalize(raw) {
                            return .hostname(host)
                        }
                        n += size
                    }
                    return .unavailable
                }
                p += length
            }
            return .unavailable
        }

        private static func http(_ b: [UInt8]) -> Result {
            let methods = [
                "GET ",
                "POST ",
                "HEAD ",
                "PUT ",
                "DELETE ",
                "OPTIONS ",
                "PATCH ",
                "CONNECT ",
            ]
            let prefix = String(decoding: b.prefix(8), as: UTF8.self)
            guard methods.contains(where: { prefix.hasPrefix($0) || $0.hasPrefix(prefix) }) else {
                return .unavailable
            }
            guard let end = b.indices.dropLast(3).first(
                where: {
                    b[$0 ..< ($0 + 4)].elementsEqual(
                        [
                            13,
                            10,
                            13,
                            10
                        ]
                    )
                }
            ) else {
                return .needMore
            }
            // A binary request body must not invalidate a readable Host header.
            guard let text = String(bytes: b.prefix(end), encoding: .utf8) else {
                return .unavailable
            }
            for line in text.components(separatedBy: "\r\n").dropFirst() {
                guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "host" else {
                    continue
                }
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                let raw: String
                if value.hasPrefix("["), let bracket = value.firstIndex(of: "]") {
                    raw = String(value[value.index(after: value.startIndex) ..< bracket])
                } else {
                    raw = String(value.split(separator: ":", maxSplits: 1).first ?? "")
                }
                if let host = Firewall.Hostname.normalize(raw) {
                    return .hostname(host)
                }
            }
            return .unavailable
        }

        private static func u16(_ b: [UInt8], _ p: Int) -> Int {
            Int(b[p]) << 8 | Int(b[p + 1])
        }
    }
}
