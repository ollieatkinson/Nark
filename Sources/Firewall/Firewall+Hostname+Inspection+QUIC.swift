import CommonCrypto
import CryptoKit
import Foundation

extension Firewall.Hostname.Inspection {

    /// RFC 9001 / 9369 client Initial packets use publicly derivable keys.
    /// Application data and ECH's encrypted inner ClientHello are never opened.
    public struct QUIC: Sendable {

        private var keys: Keys?
        private var largest: UInt64?
        private var bytes: [UInt8] = []
        private var present: [Bool] = []
        private var contiguous = 0
        private var packets = 0
        private var wireBytes = 0
        public init() {}

        /// Feed complete UDP datagrams. CRYPTO offsets permit reordering,
        /// retransmission and a ClientHello split across multiple Initial packets.
        public mutating func inspect(_ datagram: Data) -> Result {
            guard
                !datagram.isEmpty, datagram.count <= 65_535,
                wireBytes <= 65_536 - datagram.count
            else {
                return .unavailable
            }
            wireBytes += datagram.count
            var cursor = Cursor(bytes: Array(datagram))
            do {
                while cursor.remaining > 0 {
                    let start = cursor.position
                    let first = try cursor.byte()
                    guard first & 0xc0 == 0xc0 else {
                        break
                    }
                    let version = try cursor.integer(count: 4)
                    guard let format = Format(rawValue: version) else {
                        return .unavailable
                    }
                    let dcid = try cursor.connectionID()
                    _ = try cursor.connectionID()
                    // Only Initials carry publicly readable client handshake data.
                    guard (first >> 4) & 3 == format.initialType else {
                        break
                    }
                    try cursor.skip(try cursor.variable()) // Retry / NEW_TOKEN token
                    let length = try cursor.variable()
                    let pnOffset = cursor.position - start
                    let protected = try cursor.take(length)
                    packets += 1
                    guard packets <= 16, protected.count >= 20 else {
                        return .unavailable
                    }
                    if keys?.cid != dcid || keys?.format != format {
                        keys = Keys(cid: dcid, format: format)
                        largest = nil
                        bytes = []
                        present = []
                        contiguous = 0
                    }
                    guard let keys else {
                        return .unavailable
                    }
                    var header = Array(cursor.bytes[start ..< (start + pnOffset)])
                    let mask = try keys.mask(sample: Array(protected[4 ..< 20]))
                    header[0] ^= mask[0] & 0x0f
                    guard header[0] & 0x0c == 0 else {
                        return .unavailable
                    }
                    let pnSize = Int(header[0] & 3) + 1
                    var truncated: UInt64 = 0
                    for i in 0 ..< pnSize {
                        let byte = protected[i] ^ mask[i + 1]
                        header.append(byte)
                        truncated = truncated << 8 | UInt64(byte)
                    }
                    let number = packetNumber(truncated, count: pnSize)
                    var nonce = keys.iv
                    for i in 0 ..<
                        8
                    {
                        nonce[11 - i] ^= UInt8(truncatingIfNeeded: number >> (i * 8))
                    }
                    let box = try AES.GCM.SealedBox(
                        nonce: AES.GCM.Nonce(data: nonce),
                        ciphertext: protected[pnSize ..<
                            (protected.count - 16)],
                        tag: protected.suffix(16)
                    )
                    let payload = try AES.GCM.open(box, using: keys.key, authenticating: header)
                    largest = max(largest ?? 0, number)
                    try frames(Array(payload))
                    if contiguous >= 4 {
                        let result = Firewall.Hostname.Inspection
                            .clientHello(Array(bytes.prefix(contiguous)))
                        if result != .needMore {
                            return result
                        }
                    }
                }
                return keys == nil ? .unavailable : .needMore
            } catch { return .unavailable }
        }

        private mutating func frames(_ payload: [UInt8]) throws {
            var c = Cursor(bytes: payload)
            while c.remaining > 0 {
                let kind = try c.variable()
                switch kind {
                    case 0, 1:
                        break // PADDING, PING
                    case 2, 3: // ACK, ACK_ECN
                        _ = try c.variable()
                        _ = try c.variable()
                        let ranges = try c.variable()
                        guard ranges <= c.remaining / 2 else {
                            throw Invalid.packet
                        }
                        _ = try c.variable()
                        for _ in 0 ..< ranges {
                            _ = try c.variable()
                            _ = try c.variable()
                        }
                        if kind == 3 {
                            for _ in 0 ..< 3 {
                                _ = try c.variable()
                            }
                        }
                    case 6: // CRYPTO
                        let offset = try c.variable()
                        let length = try c.variable()
                        guard
                            offset <= limit,
                            length <= limit - offset
                        else {
                            throw Invalid.packet
                        }
                        let fragment = try c.take(length)
                        if offset + length > bytes.count {
                            bytes += repeatElement(0, count: offset + length - bytes.count)
                            present += repeatElement(false, count: offset + length - present.count)
                        }
                        for (index, byte) in fragment.enumerated() {
                            let position = offset + index
                            guard !present[position] || bytes[position] == byte
                            else {
                                throw Invalid.packet
                            }
                            bytes[position] = byte
                            present[position] = true
                        }
                        while contiguous < present.count, present[contiguous] {
                            contiguous += 1
                        }
                    default:
                        throw Invalid.packet // Other frames cannot carry Initial CRYPTO.
                }
            }
        }

        private func packetNumber(_ truncated: UInt64, count: Int) -> UInt64 {
            let expected = (largest ?? 0) + 1
            let window: UInt64 = 1 << (count * 8)
            let half = window / 2
            var candidate = (expected & ~(window - 1)) | truncated
            if candidate + half <= expected, candidate < (1 << 62) - window {
                candidate += window
            } else if candidate > expected + half, candidate >= window {
                candidate -= window
            }
            return candidate
        }
    }
}

private enum Invalid: Error {
    case packet
}

private enum Format: UInt64, Sendable {
    case v1 = 1
    case v2 = 0x6b3343cf
    var initialType: UInt8 {
        self == .v1 ? 0 : 1
    }

    var label: String {
        self == .v1 ? "quic" : "quicv2"
    }

    var salt: [UInt8] {
        self == .v1
            ? [
                0x38,
                0x76,
                0x2c,
                0xf7,
                0xf5,
                0x59,
                0x34,
                0xb3,
                0x4d,
                0x17,
                0x9a,
                0xe6,
                0xa4,
                0xc8,
                0x0c,
                0xad,
                0xcc,
                0xbb,
                0x7f,
                0x0a
            ]
            : [
                0x0d,
                0xed,
                0xe3,
                0xde,
                0xf7,
                0x00,
                0xa6,
                0xdb,
                0x81,
                0x93,
                0x81,
                0xbe,
                0x6e,
                0x26,
                0x9d,
                0xcb,
                0xf9,
                0xbd,
                0x2e,
                0xd9
            ]
    }
}

private struct Keys: Sendable {

    let cid: [UInt8]
    let format: Format
    let key: SymmetricKey
    let iv: [UInt8]
    let hp: [UInt8]
    init(cid: [UInt8], format: Format) {
        self.cid = cid
        self.format = format
        let initial = HKDF<SHA256>.extract(
            inputKeyMaterial: SymmetricKey(data: cid),
            salt: format.salt
        )
        let client = Self.expand(initial, label: "client in", count: 32)
        key = Self.expand(client, label: format.label + " key", count: 16)
        iv = Self.expand(client, label: format.label + " iv", count: 12)
            .withUnsafeBytes { Array($0) }
        hp = Self.expand(client, label: format.label + " hp", count: 16)
            .withUnsafeBytes { Array($0) }
    }

    private static func expand<S: ContiguousBytes>(
        _ secret: S,
        label: String,
        count: Int
    ) -> SymmetricKey {
        let label = Array(("tls13 " + label).utf8)
        let info = [UInt8(count >> 8), UInt8(count & 255), UInt8(label.count)] + label + [0]
        return HKDF<SHA256>.expand(pseudoRandomKey: secret, info: info, outputByteCount: count)
    }

    func mask(sample: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: 16)
        var written = 0
        let status = hp.withUnsafeBytes { key in
            sample.withUnsafeBytes { input in
                output.withUnsafeMutableBytes { target in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        key.baseAddress,
                        16,
                        nil,
                        input.baseAddress,
                        16,
                        target.baseAddress,
                        16,
                        &written
                    )
                }
            }
        }
        guard status == kCCSuccess, written == 16 else {
            throw Invalid.packet
        }
        return output
    }
}

private struct Cursor {

    let bytes: [UInt8]
    var position = 0
    var remaining: Int {
        bytes.count - position
    }

    mutating func byte() throws -> UInt8 {
        guard remaining > 0 else {
            throw Invalid.packet
        }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func integer(count: Int) throws -> UInt64 {
        try take(count).reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func variable() throws -> Int {
        let first = try byte()
        let count = 1 << Int(first >> 6)
        var value = UInt64(first & 0x3f)
        for _ in 1 ..< count {
            value = value << 8 | UInt64(try byte())
        }
        guard value <= UInt64(Int.max) else {
            throw Invalid.packet
        }
        return Int(value)
    }

    mutating func connectionID() throws -> [UInt8] {
        let count = Int(try byte())
        guard count <= 20 else {
            throw Invalid.packet
        }
        return try take(count)
    }

    mutating func skip(_ count: Int) throws {
        _ = try take(count)
    }

    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= remaining else {
            throw Invalid.packet
        }
        defer { position += count }
        return Array(bytes[position ..< (position + count)])
    }
}
