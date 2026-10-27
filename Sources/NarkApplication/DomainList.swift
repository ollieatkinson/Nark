import Firewall
import Foundation

/// The CLI and monitor use the same bounded, UTF-8 import boundary.
enum DomainList {

    static func read(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 5_000_001) ?? Data()
        guard data.count <= 5_000_000 else {
            throw Firewall.Error.message("Blocklist exceeds 5 MB.")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw Firewall.Error.message("Blocklist must be UTF-8 text.")
        }
        return text
    }
}
