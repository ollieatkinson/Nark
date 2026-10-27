import Darwin
import Foundation

/// An offline, read-only country lookup. No networking, DNS or location permission.
public struct Database: Sendable {

    private let ipv4: Data
    private let ipv6: Data
    public init(ipv4: Data, ipv6: Data) throws {
        guard ipv4.count.isMultiple(of: 10), ipv6.count.isMultiple(of: 34) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.ipv4 = ipv4
        self.ipv6 = ipv6
    }

    private static let bundled: Result<Database, any Error> = Result {
        try Database(
            ipv4: Data(
                contentsOf: Bundle.module.url(forResource: "country-v4", withExtension: "bin")!,
                options: .mappedIfSafe
            ),
            ipv6: Data(
                contentsOf: Bundle.module.url(forResource: "country-v6", withExtension: "bin")!,
                options: .mappedIfSafe
            )
        )
    }

    @concurrent public static func locate(_ addresses: [String]) async throws -> [String: String] {
        let database = try bundled.get()
        return Dictionary(
            uniqueKeysWithValues: Set(addresses)
                .map { ($0, database.country(for: $0)) }
        )
    }

    /// LOCAL denotes private/link-local/loopback addresses; ZZ denotes unavailable locations.
    public func country(for address: String) -> String {
        let host = String(
            address.split(
                separator: "%",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            .first ?? ""
        )
        var bytes = [UInt8](repeating: 0, count: 16)
        if inet_pton(AF_INET, host, &bytes) == 1 {
            return lookup(Array(bytes.prefix(4)), in: ipv4)
        }
        guard inet_pton(AF_INET6, host, &bytes) == 1 else {
            return "ZZ"
        }
        // IPv4-mapped IPv6 addresses share the IPv4 table and local-address semantics.
        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
            return lookup(Array(bytes.suffix(4)), in: ipv4)
        }
        return lookup(bytes, in: ipv6)
    }

    private func lookup(_ address: [UInt8], in data: Data) -> String {
        let n = address.count
        if n == 4 {
            if address[0] == 10 || address[0] == 127 || address[0] == 0
                || (address[0] == 172 && (16 ... 31).contains(address[1]))
                || (address[0] == 192 && address[1] == 168)
                || (address[0] == 169 && address[1] == 254) {
                return "LOCAL"
            }
            if address[0] >= 224 {
                return "ZZ"
            }
        } else {
            if address.allSatisfy({ $0 == 0 }) {
                return "ZZ"
            }
            if address.dropLast().allSatisfy({ $0 == 0 }) && address.last == 1
                || address[0] & 0xfe == 0xfc
                || (address[0] == 0xfe && address[1] & 0xc0 == 0x80) {
                return "LOCAL"
            }
            if address[0] == 0xff {
                return "ZZ"
            }
        }
        let stride = n * 2 + 2
        var low = 0
        var high = data.count / stride
        while low < high {
            let middle = (low + high) / 2
            let offset = middle * stride
            if address.lexicographicallyPrecedes(data[offset ..< (offset + n)]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        guard low > 0 else {
            return "ZZ"
        }
        let offset = (low - 1) * stride
        guard !data[(offset + n) ..< (offset + n * 2)].lexicographicallyPrecedes(address) else {
            return "ZZ"
        }
        return String(decoding: data[(offset + n * 2) ..< (offset + stride)], as: UTF8.self)
    }
}

public struct World: Equatable, Sendable {

    public static let width = 720
    public static let height = 290
    private let pixels: Data
    public static let bundled = World(
        pixels: (try? Data(
            contentsOf: Bundle.module.url(
                forResource: "world",
                withExtension: "bin"
            )!
        )) ?? Data()
    )
    public func country(x: Int, y: Int) -> String? {
        guard (0 ..< Self.width).contains(x), (0 ..< Self.height).contains(y) else {
            return nil
        }
        let offset = (y * Self.width + x) * 2
        guard offset + 1 < pixels.count, pixels[offset] != 32 else {
            return nil
        }
        return String(decoding: pixels[offset ..< (offset + 2)], as: UTF8.self)
    }
}

public struct Coordinate: Codable, Equatable, Sendable {

    public let latitude: Double
    public let longitude: Double
}

extension World {

    /// Natural Earth label points are country-level anchors, not endpoint locations.
    public static let countryPoints: [String: Coordinate] = {
        guard let url = Bundle.module.url(forResource: "country-points", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Coordinate].self, from: data)) ?? [:]
    }()
}
