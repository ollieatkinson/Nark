import Firewall
import Foundation

/// Fetches source text in the user process. The provider only validates and commits policy.
public enum BlocklistSource {

    public static let limit = 8_000_000
    @concurrent public static func read(_ source: String) async throws -> Firewall.Blocklist.Import {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        let name: String
        let canonical: String
        if let url = URL(string: source), url.scheme != nil {
            guard url.scheme?.lowercased() == "https",
                  url.host != nil,
                  url.user == nil,
                  url.password == nil else {
                throw Firewall.Error.message("Use an HTTPS blocklist URL without credentials, or a local file path.")
            }
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw Firewall.Error.message("Invalid blocklist URL.")
            }
            components.scheme = "https"
            components.host = components.host?.lowercased()
            if components.percentEncodedPath.isEmpty {
                components.percentEncodedPath = "/"
            }
            guard let normalized = components.url else {
                throw Firewall.Error.message("Invalid blocklist URL.")
            }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            let session = URLSession(
                configuration: config,
                delegate: RedirectPolicy(),
                delegateQueue: nil
            )
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(from: normalized)
            guard let response = response as? HTTPURLResponse,
                  (200 ... 299).contains(response.statusCode) else {
                throw Firewall.Error.message("Blocklist download failed (HTTP response).")
            }
            guard response.url?.scheme == "https",
                  response.expectedContentLength <= Int64(limit) else {
                throw Firewall.Error.message("Blocklist exceeds 8 MB or redirected away from HTTPS.")
            }
            var data = Data()
            data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
            for try await byte in bytes {
                guard data.count < limit else {
                    throw Firewall.Error.message("Blocklist exceeds 8 MB.")
                }
                data.append(byte)
            }
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw Firewall.Error.message("Blocklist must be UTF-8 text.")
            }
            text = decoded
            name = url.host ?? "Blocklist"
            canonical = normalized.absoluteString
        } else {
            let url = URL(fileURLWithPath: (source as NSString).expandingTildeInPath).standardizedFileURL
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var data = Data()
            while let chunk = try file.read(upToCount: 64_000), !chunk.isEmpty {
                guard data.count + chunk.count <= limit else {
                    throw Firewall.Error.message("Blocklist exceeds 8 MB.")
                }
                data.append(chunk)
            }
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw Firewall.Error.message("Blocklist must be UTF-8 text.")
            }
            text = decoded
            name = url.lastPathComponent
            canonical = url.path
        }
        _ = try Firewall.Runtime.parseBlocklist(text, limit: limit) // Fail before changing any provider state.
        let preset = Firewall.Blocklist.community.first { $0.source == canonical }
        return .init(
            id: preset?.id,
            name: preset?.name ?? name,
            source: canonical,
            attribution: preset?.attribution ?? "User supplied source",
            text: text
        )
    }
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}
