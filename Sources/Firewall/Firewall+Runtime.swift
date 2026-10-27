import Foundation
import Synchronization
import Vocabulary

/// Owns policy and bounded activity, independently of the terminal client's lifetime.
extension Firewall {

    public final class Runtime: Sendable {

        public let events = Events()
        private let state: Mutex<Firewall.Snapshot>
        private let blocklists: Mutex<Firewall.BlocklistStore>
        private let traffic = Mutex(Firewall.TrafficTracker())
        private let recordings = Mutex<[UUID: Firewall.Recording.Session]>([:])
        private let rulesURL: URL?
        private let historyURL: URL?
        public init(
            directory: URL? = nil,
            onHistoryFailure: (any Swift.Error) -> Void = { _ in }
        ) throws {
            rulesURL = directory?.appendingPathComponent("rules.json")
            historyURL = directory?.appendingPathComponent("history.json")
            if let directory {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            let rules: [Firewall.Rule]
            if let rulesURL, FileManager.default.fileExists(atPath: rulesURL.path) {
                rules = try JSONDecoder()
                    .decode(
                        [Firewall.Rule].self, from: Data(contentsOf: rulesURL)
                    )
                    .map { try $0.validated() }
            } else {
                rules = []
            }
            var snapshot = Firewall.Snapshot(rules: rules)
            if let historyURL {
                do {
                    let old = try JSONDecoder().decode(
                        Firewall.Snapshot.self,
                        from: Data(contentsOf: historyURL)
                    )
                    snapshot.rows = Array(old.rows.prefix(2000))
                    snapshot.totalAllowed = old.totalAllowed
                    snapshot.totalBlocked = old.totalBlocked
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    // A new installation has no activity checkpoint yet.
                } catch { onHistoryFailure(error) }
            }
            state = Mutex(snapshot)
            blocklists = Mutex(try Firewall.BlocklistStore(directory: directory))
        }

        public func snapshot() -> Firewall.Snapshot {
            var snapshot = state.withLock { $0 }
            snapshot.traffic = traffic.withLock { $0.summary }
            blocklists.withLock { store in
                snapshot.blocklists = store.lists.map(\.summary)
                snapshot
                    .blocklistMatches = Dictionary(uniqueKeysWithValues: snapshot.rows
                        .compactMap { row in
                            guard row.direction == .outbound else {
                                return nil
                            }
                            return store.match(host: row.host, address: row.address).map { (
                                row.id.uuidString,
                                $0
                            ) }
                        })
            }
            return snapshot
        }

        public func reportTraffic(id: UUID, received: Int64, sent: Int64, closed: Bool) {
            guard let (connection, delta) = traffic.withLock({ $0.report(
                id: id,
                received: received,
                sent: sent,
                closed: closed
            ) }) else {
                return
            }
            state.withLock { state in
                if
                    let index = state.rows
                        .firstIndex(where: { $0.sharesDestination(with: connection) })
                {
                    state.rows[index].traffic = (state.rows[index].traffic ?? .init()) + delta
                }
            }
        }

        public func isBlocked(
            app: String,
            host: String?,
            address: String,
            direction: Firewall.Direction = .outbound
        ) -> Bool {
            decision(app: app, host: host, address: address, direction: direction).verdict == .drop
        }

        public func decision(
            app: String,
            host: String?,
            address: String,
            direction: Firewall.Direction = .outbound
        ) -> Firewall.Decision {
            guard direction == .outbound else {
                return Firewall.Decision(verdict: .allow)
            }
            return state.withLock { state in
                if let rule = state.rules.first(where: {
                    $0.matches(app: app, host: host, address: address, direction: direction)
                }) {
                    return Firewall.Decision(verdict: .drop, rule: rule.id)
                }
                if let list = blocklists.withLock({ $0.match(host: host, address: address) }) {
                    return Firewall.Decision(verdict: .drop, blocklist: list)
                }
                return Firewall.Decision(verdict: .allow)
            }
        }

        public func evaluate(_ connection: Firewall.Connection) -> Firewall.Decision {
            let decision = decision(
                app: connection.app, host: connection.host, address: connection.address,
                direction: connection.direction
            )
            var connection = connection
            connection.blocked = decision.verdict == .drop
            record(connection)
            // Observation is supplementary: delivery/encoding failure cannot change a verdict.
            if let event = try? connection.event(decision: decision) {
                _ = try? events.send(event)
            }
            return decision
        }

        deinit { events.finish() }
        public func record(_ row: Firewall.Connection) {
            traffic.withLock { $0.observe(row) }
            recordings.withLock { sessions in
                let now = Date()
                sessions = sessions.filter { !$0.value.expired(at: now) }
                for id in Array(sessions.keys) {
                    sessions[id]?.record(row, at: now)
                }
            }
            state.withLock { state in
                if row.blocked {
                    state.totalBlocked += 1
                } else {
                    state.totalAllowed += 1
                }
                if let i = state.rows.firstIndex(where: {
                    $0.sharesDestination(with: row)
                }) {
                    var existing = state.rows.remove(at: i)
                    existing.count += 1
                    existing.lastSeen = row.lastSeen
                    existing.localAddress = row.localAddress
                    existing.localPort = row.localPort
                    state.rows.insert(existing, at: 0)
                } else {
                    state.rows.insert(row, at: 0)
                }
                if state.rows.count > 2000 {
                    state.rows.removeLast(state.rows.count - 2000)
                }
            }
        }

        public func checkpoint() throws {
            try state.withLock { state in
                if let historyURL {
                    try Self.save(state, to: historyURL)
                }
            }
        }

        public func handle(_ request: Firewall.Request) -> Firewall.Response {
            if case .blocklist(let request) = request {
                do {
                    if case .read(let id) = request {
                        guard let list = blocklists.withLock({ $0.lists.first { $0.id == id } })
                        else {
                            throw Firewall.Error.message("Blocklist no longer exists.")
                        }
                        return Firewall.Response(blocklist: list)
                    }
                    try blocklists.withLock { try $0.apply(request) }
                    return Firewall.Response(snapshot: snapshot())
                } catch { return Firewall.Response(error: error.localizedDescription) }
            }
            if case .recording(let request) = request {
                do { return Firewall.Response(recording: try recording(request)) }
                catch { return Firewall.Response(error: error.localizedDescription) }
            }
            do {
                try state.withLock { state in
                    var rules = state.rules
                    switch request {
                        case .recording,
                             .blocklist:
                            return // Handled before taking the policy lock.
                        case .snapshot:
                            return
                        case .add(let rule):
                            let rule = try rule.validated()
                            if
                                !rules
                                    .contains(where: { $0.app == rule.app && $0.domain == rule.domain }
                                    )
                            {
                                rules.append(rule)
                            }
                        case .remove(let id):
                            rules.removeAll { $0.id == id }
                        case .toggle(let id):
                            guard let i = rules.firstIndex(where: { $0.id == id }) else {
                                throw Firewall.Error.message("Rule no longer exists.")
                            }
                            rules[i].enabled.toggle()
                        case .importDomains(let text):
                            let domains = try Self.parseBlocklist(text)
                            for domain in domains
                                where !rules
                                .contains(where: { $0.app == nil && $0.domain == domain })
                            {
                                rules.append(try Firewall.Rule(domain: domain))
                            }
                        case .clearHistory:
                            var cleared = state
                            cleared.rows = []
                            cleared.totalAllowed = 0
                            cleared.totalBlocked = 0
                            traffic.withLock { $0.clear() }
                            if let historyURL {
                                try Self.save(cleared, to: historyURL)
                            }
                            state = cleared
                            return
                    }
                    if let rulesURL {
                        try Self.save(rules, to: rulesURL)
                    }
                    state.rules = rules
                }
                return Firewall.Response(snapshot: snapshot())
            } catch { return Firewall.Response(error: error.localizedDescription) }
        }

        public func recording(_ request: Firewall.Recording.Request) throws -> Firewall.Recording.Batch {
            return try recordings.withLock { sessions in
                let now = Date()
                sessions = sessions.filter { !$0.value.expired(at: now) }
                switch request {
                    case .start(let application):
                        guard sessions.count < 8
                        else {
                            throw Firewall.Error.message("Too many active recordings.")
                        }
                        var session = Firewall.Recording.Session(
                            application: try application.validated(),
                            now: now
                        )
                        let batch = try session.read(after: 0, at: now)
                        sessions[session.id] = session
                        return batch
                    case .read(let cursor), .stop(let cursor):
                        guard var session = sessions[cursor.id] else {
                            throw Firewall.Error
                                .message(
                                    "Recording expired or the filter restarted. The saved log is incomplete."
                                )
                        }
                        if case .stop = request {
                            session.endedAt = session.endedAt ?? now
                        }
                        let batch = try session.read(after: cursor.after, at: now)
                        sessions[cursor.id] = session
                        return batch
                    case .close(let id):
                        guard var session = sessions.removeValue(forKey: id) else {
                            throw Firewall.Error.message("Recording no longer exists.")
                        }
                        session.endedAt = session.endedAt ?? now
                        return try session.read(after: session.sequence, at: now)
                }
            }
        }

        /// The root-owned provider must reopen state while the login session is locked.
        /// The enclosing directory is private; keep each atomic replacement owner-only too.
        private static func save<Value: Encodable>(_ value: Value, to url: URL) throws {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }

        public static func parseBlocklist(
            _ text: String,
            limit: Int = 5_000_000
        ) throws -> [String] {
            guard text.utf8.count <= limit else {
                throw Firewall.Error.message("Blocklist exceeds \(limit / 1_000_000) MB.")
            }
            var result = Set<String>()
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if
                    trimmed.hasPrefix("!") || ["[Adblock Plus]", "[Adblock Plus 2.0]"]
                        .contains(trimmed)
                {
                    continue
                }
                if trimmed.hasPrefix("||"), trimmed.hasSuffix("^") {
                    let raw = String(trimmed.dropFirst(2).dropLast())
                    guard
                        !raw.contains(where: { "/*^$|@".contains($0) }),
                        let domain = Firewall.Hostname.normalize(raw),
                        domain == raw.lowercased()
                    else {
                        throw Firewall.Error
                            .message("Unsupported anchored domain rule on line \(index + 1).")
                    }
                    result.insert(domain)
                    continue
                }
                let fields = line.split(
                    separator: "#", maxSplits: 1, omittingEmptySubsequences: false
                )[0]
                    .split(whereSeparator: { $0.isWhitespace })
                if fields.isEmpty {
                    continue
                }
                let names: ArraySlice<Substring>
                if
                    fields.count > 1
                    && ["0.0.0.0", "127.0.0.1", "::", "::1"].contains(String(fields[0]))
                {
                    names = fields.dropFirst()
                } else if fields.count == 1 {
                    names = fields[...]
                } else {
                    throw Firewall.Error.message(
                        "Unsupported blocklist syntax on line \(index + 1). Use domains or hosts-file format."
                    )
                }
                for name in names {
                    guard let domain = Firewall.Hostname.normalize(String(name)) else {
                        throw Firewall.Error.message("Invalid domain on line \(index + 1).")
                    }
                    if domain != "localhost" && domain != "localhost.localdomain" {
                        result.insert(domain)
                    }
                }
            }
            return result.sorted()
        }
    }
}
