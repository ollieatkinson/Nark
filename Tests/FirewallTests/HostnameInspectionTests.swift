import Firewall
import Foundation
import Testing

@Suite struct HostnameInspectionTests {

    typealias Peek = Firewall.Hostname.Inspection
    @Test func http_host_and_partial_headers() {
        #expect(Peek.inspect(Data("GET / HTTP/1.1\r\nHost: ExAmple.com:80\r\n\r\n".utf8)) == .hostname("example.com"))
        #expect(Peek.inspect(Data("GET / HTTP/1.1\r\nHost:".utf8)) == .needMore)
        #expect(Peek.inspect(Data("SSH-2.0-test\r\n".utf8)) == .unavailable)
        #expect(Peek.inspect(
            Data("POST / HTTP/1.1\r\nHost: upload.test\r\n\r\n".utf8) + Data(
                [
                    0xff,
                    0xfe
                ]
            )
        ) == .hostname("upload.test"))
    }

    @Test func chrome_shaped_hello_skips_grease_and_unknown_extensions() {
        // GREASE, key-share sized padding, and ECH GREASE before SNI. GREASE ECH
        // leaves the visible name intact; this does not recover real inner ECH SNI.
        let extra = u16(0x2a2a) + u16(0) + u16(51) + u16(1800) + [UInt8](repeating: 1, count: 1800)
            + u16(0xfe0d) + u16(128) + [UInt8](repeating: 0xa5, count: 128)
        let record = tlsRecord(clientHello(host: "chrome.test", beforeSNI: extra))
        #expect(Peek.inspect(Data(record)) == .hostname("chrome.test"))
        var session = Peek.Session(.tcp)
        #expect(session.inspect(Data(record.prefix(80)), at: 0) == .needMore)
        #expect(session.inspect(Data(record.prefix(500)), at: 0) == .needMore)
        #expect(session.inspect(Data(record.dropFirst(500)), at: 500) == .hostname("chrome.test"))
        var gap = Peek.Session(.tcp)
        #expect(gap.inspect(Data(record), at: 1) == .unavailable)
        var conflict = Peek.Session(.tcp)
        #expect(conflict.inspect(Data(record.prefix(5)), at: 0) == .needMore)
        #expect(conflict.inspect(Data([0]), at: 0) == .unavailable)
    }

    @Test func tls_sni_handles_fragmented_records_and_truncation() {
        let handshake = clientHello(host: "api.example.com")
        let record = tlsRecord(handshake)
        #expect(Peek.inspect(Data(record)) == .hostname("api.example.com"))
        for size in 0 ..< record.count {
            #expect(Peek.inspect(Data(record.prefix(size))) == .needMore)
        }
        let fragmented = tlsRecord(Array(handshake.prefix(20))) + tlsRecord(Array(handshake.dropFirst(20)))
        #expect(Peek.inspect(Data(fragmented)) == .hostname("api.example.com"))
    }

    @Test func malformed_and_oversized_packets_do_not_crash_or_wait_forever() {
        #expect(Peek.inspect(Data([22, 3, 3, 255, 255])) == .unavailable)
        #expect(Peek.inspect(Data("GET ".utf8) + Data(repeating: 65, count: Peek.limit)) == .unavailable)
        var generator = Generator()
        for size in 0 ..< 600 {
            let bytes = (0 ..< size).map { _ in UInt8.random(in: 0 ... 255, using: &generator) }
            _ = Peek.inspect(Data(bytes))
            _ = Peek.inspect(Data([22, 3, 3, UInt8(size >> 8), UInt8(size & 255)] + bytes))
        }
    }

    private func clientHello(host: String, beforeSNI: [UInt8] = []) -> [UInt8] {
        let name = Array(host.utf8)
        let entry = [UInt8(0)] + u16(name.count) + name
        let sni = u16(entry.count) + entry
        let ext = beforeSNI + u16(0) + u16(sni.count) + sni
        let body = [UInt8(3), 3] + [UInt8](repeating: 0, count: 32) + [0] + [0, 2, 0x13, 1] + [1, 0]
            + u16(ext.count) + ext
        return [
            1,
            UInt8(body.count >> 16),
            UInt8((body.count >> 8) & 255),
            UInt8(body.count & 255),
        ]
            + body
    }

    private func tlsRecord(_ body: [UInt8]) -> [UInt8] {
        [22, 3, 3] + u16(body.count) + body
    }

    private func u16(_ n: Int) -> [UInt8] {
        [UInt8(n >> 8), UInt8(n & 255)]
    }

    private struct Generator: RandomNumberGenerator {

        var state: UInt64 = 42
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return state
        }
    }
}
