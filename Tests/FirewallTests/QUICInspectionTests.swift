import CommonCrypto
import CryptoKit
import Firewall
import Foundation
import Testing

@Suite struct QUICInspectionTests {

    typealias Peek = Firewall.Hostname.Inspection

    @Test(arguments: [9001, 9369])
    func published_client_initial_vectors_reveal_sni(rfc: Int) throws {
        let packet = try vector(rfc)
        var quic = Peek.QUIC()
        #expect(quic.inspect(packet) == .hostname("example.com"))
        var session = Peek.Session(.quic)
        #expect(session.inspect(packet, at: 0) == .hostname("example.com"))
        let runtime = try Firewall.Runtime()
        _ = runtime.handle(.add(try Firewall.Rule(domain: "example.com")))
        if case .hostname(let name) = quic.inspect(packet) {
            #expect(runtime.evaluate(
                .init(
                    app: "/test/browser",
                    host: name,
                    address: "192.0.2.1",
                    port: "443",
                    transport: "UDP",
                    blocked: false
                )
            )
            .verdict == .drop)
        } else {
            Issue.record("Retransmitted Initial lost the hostname")
        }
    }

    @Test func fragmented_crypto_reorders_retransmits_and_coalesces() throws {
        let hello = try handshake()
        let first = crypto(Array(hello.prefix(80)), offset: 0)
        let second = crypto(Array(hello.dropFirst(80)), offset: 80)
        let a = try packet(first, number: 2)
        let b = try packet(second, number: 3)
        var quic = Peek.QUIC()
        #expect(quic.inspect(b) == .needMore)
        #expect(quic.inspect(b) == .needMore)
        #expect(quic.inspect(a) == .hostname("example.com"))
        var coalesced = Peek.QUIC()
        #expect(coalesced.inspect(a + b) == .hostname("example.com"))
        var frames = Peek.QUIC()
        // PING and a valid ACK may appear before/between CRYPTO frames.
        #expect(try frames.inspect(packet([1, 2, 0, 0, 0, 0] + second + first)) == .hostname("example.com"))
    }

    @Test func authentication_and_header_integrity_are_required() throws {
        let original = try vector(9001)
        for position in [0, 6, 18, 80, 1199] {
            var altered = original
            altered[position] ^= 1
            var quic = Peek.QUIC()
            #expect(quic.inspect(altered) == .unavailable)
        }
        // A server Initial must not be interpreted as a client's hostname.
        var server = Peek.QUIC()
        #expect(server.inspect(
            Data(hex: "cf000000010008f067a5502a4262b5004075c0d95a482cd0991cd25b0aac406a5816b6394100")
        )
            == .unavailable)
    }

    @Test func truncated_unsupported_and_hostile_packets_are_bounded() throws {
        let original = try vector(9369)
        for count in 0 ..< original.count {
            var quic = Peek.QUIC()
            #expect(quic.inspect(original.prefix(count)) == .unavailable)
        }
        var unknown = try vector(9001)
        unknown[4] = 99
        var quic = Peek.QUIC()
        #expect(quic.inspect(unknown) == .unavailable)
        #expect(quic.inspect(Data(repeating: 0xff, count: 70_000)) == .unavailable)
        var oversize = Peek.QUIC()
        #expect(try oversize.inspect(packet([6] + variable(Peek.limit) + [1, 0])) == .unavailable)
        var conflict = Peek.QUIC()
        #expect(try conflict.inspect(packet(crypto([1, 0], offset: 0))) == .needMore)
        #expect(try conflict.inspect(packet(crypto([2, 0], offset: 0), number: 3)) == .unavailable)
        var budget = Peek.QUIC()
        let ping = try packet([1])
        for _ in 0 ..< 16 {
            #expect(budget.inspect(ping) == .needMore)
        }
        #expect(budget.inspect(ping) == .unavailable)
    }

    @Test func packet_numbers_reconstruct_across_a_one_byte_wrap() throws {
        let hello = try handshake()
        var quic = Peek.QUIC()
        #expect(try quic.inspect(packet(crypto(Array(hello.prefix(80)), offset: 0), number: 255)) == .needMore)
        #expect(try quic.inspect(
            packet(
                crypto(Array(hello.dropFirst(80)), offset: 80),
                number: 256
            )
        ) == .hostname("example.com"))
    }

    private func vector(_ rfc: Int) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: "rfc\(rfc)-client-initial",
            withExtension: "hex",
            subdirectory: "Fixtures"
        ))
        return Data(hex: try String(contentsOf: url, encoding: .utf8))
    }

    private func handshake() throws -> [UInt8] {
        // RFC 9001 A.2 plaintext, independent of the implementation's TLS builder.
        Array(
            Data(
                hex: """
                010000ed0303ebf8fa56f12939b9584a3896472ec40bb863cfd3e86804fe3a47f06a2b69484c00000413011302010000c000000010000e00000b6578616d706c652e636f6dff01000100000a00080006001d0017001800100007000504616c706e000500050100000000003300260024001d00209370b2c9caa47fbabaf4559fedba753de171fa71f50f1ce15d43e994ec74d748002b0003020304000d0010000e0403050306030203080408050806002d00020101001c00024001003900320408ffffffffffffffff05048000ffff07048000ffff0801100104800075300901100f088394c8f03e51570806048000ffff
                """
            )
        )
    }

    private func crypto(_ bytes: [UInt8], offset: Int) -> [UInt8] {
        [6] + variable(offset) + variable(bytes.count) + bytes
    }

    private func variable(_ n: Int) -> [UInt8] {
        if n < 64 {
            return [UInt8(n)]
        }
        if n < 16_384 {
            return [0x40 | UInt8(n >> 8), UInt8(n & 255)]
        }
        return [
            0x80 | UInt8(n >> 24),
            UInt8((n >> 16) & 255),
            UInt8((n >> 8) & 255),
            UInt8(n & 255)
        ]
    }

    /// Synthetic fragmentation uses the published RFC 9001 A.1 keys, rather than
    /// duplicating production key derivation. RFC vectors cover the full derivation.
    private func packet(_ payload: [UInt8], number: UInt64 = 2) throws -> Data {
        let key = SymmetricKey(data: Data(hex: "1f369613dd76d5467730efcbe3b1a22d"))
        var iv = Array(Data(hex: "fa044b2f42a3fd3b46fb255c"))
        for i in 0 ..< 8 {
            iv[11 - i] ^= UInt8(truncatingIfNeeded: number >> (8 * i))
        }
        let plaintext = payload + [UInt8](repeating: 0, count: max(0, 32 - payload.count))
        var header = Array(Data(hex: "c000000001088394c8f03e5157080000"))
        header += variable(plaintext.count + 17)
        let pnOffset = header.count
        header.append(UInt8(truncatingIfNeeded: number))
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: AES.GCM.Nonce(data: iv),
            authenticating: header
        )
        var packet = header + sealed.ciphertext + sealed.tag
        let hp = Data(hex: "9f50449e04a0e810283a1e9933adedd2")
        let sample = Array(packet[(pnOffset + 4) ..< (pnOffset + 20)])
        var mask = [UInt8](repeating: 0, count: 16)
        var written = 0
        let status = hp.withUnsafeBytes { key in
            sample.withUnsafeBytes { input in
                mask.withUnsafeMutableBytes { output in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        key.baseAddress,
                        16,
                        nil,
                        input.baseAddress,
                        16,
                        output.baseAddress,
                        16,
                        &written
                    )
                }
            }
        }
        #expect(status == kCCSuccess)
        packet[0] ^= mask[0] & 0xf
        packet[pnOffset] ^= mask[1]
        return Data(packet)
    }
}

private extension Data {

    init(hex: String) {
        let characters = Array(hex.filter { !$0.isWhitespace })
        self.init(
            stride(from: 0, to: characters.count, by: 2).map {
                UInt8(String(characters[$0 ... ($0 + 1)]), radix: 16)!
            }
        )
    }
}
