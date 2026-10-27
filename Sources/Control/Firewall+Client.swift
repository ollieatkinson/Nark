import Firewall
import Foundation
import Vocabulary

extension Firewall {

    public struct Client: Sendable {

        private let respond: @Sendable (Firewall.Request) async throws -> Firewall.Response
        public init(request: @escaping @Sendable (Firewall.Request) async throws -> Firewall.Snapshot) {
            respond = { Firewall.Response(snapshot: try await request($0)) }
        }

        package init(response: @escaping @Sendable (Firewall.Request) async throws -> Firewall.Response) {
            respond = response
        }

        public func request(_ request: Firewall.Request) async throws -> Firewall.Snapshot {
            let reply = try await response(to: request)
            guard let snapshot = reply.snapshot else {
                throw Firewall.Error.message("Invalid snapshot reply.")
            }
            return snapshot
        }

        public func blocklist(_ id: UUID) async throws -> Firewall.Blocklist {
            let reply = try await response(to: .blocklist(.read(id)))
            guard let list = reply.blocklist else {
                throw Firewall.Error.message("Invalid blocklist reply.")
            }
            return list
        }

        public func recording(_ request: Firewall.Recording.Request) async throws -> Firewall.Recording.Batch {
            let reply = try await response(to: .recording(request))
            guard let batch = reply.recording else {
                throw Firewall.Error.message("Invalid recording reply.")
            }
            return batch
        }

        private func response(to request: Firewall.Request) async throws -> Firewall.Response {
            let reply = try await respond(request)
            if let error = reply.error {
                throw Firewall.Error.message(error)
            }
            return reply
        }

        public static func live(service: String, team: String) -> Self {
            Self(
                response: { request in
                    let data = try JSONEncoder().encode(Message(request))
                    let connection = NSXPCConnection(machServiceName: service, options: .privileged)
                    connection.remoteObjectInterface = NSXPCInterface(with: FirewallService.self)
                    connection.setCodeSigningRequirement(
                        "anchor apple generic and identifier \"\(ExtensionConfiguration.extensionID)\" and certificate leaf[subject.OU] = \"\(team)\""
                    )
                    let reply: Data = try await withCheckedThrowingContinuation { continuation in
                        let pending = PendingReply(continuation: continuation, connection: connection)
                        connection.invalidationHandler = {
                            pending.finish(
                                .failure(
                                    Firewall.Error.message(
                                        "Filter disconnected. Install and enable the signed extension first."
                                    )
                                )
                            )
                        }
                        connection.interruptionHandler = {
                            pending.finish(.failure(Firewall.Error.message("Filter restarted. Try again.")))
                        }
                        connection.resume()
                        guard let proxy = connection.remoteObjectProxyWithErrorHandler(
                            {
                                pending.finish(.failure($0))
                            }
                        ) as? FirewallService else {
                            pending.finish(.failure(Firewall.Error.message("Cannot connect to filter.")))
                            return
                        }
                        proxy.request(data) { pending.finish(.success($0)) }
                        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                            pending.finish(.failure(Firewall.Error.message("Filter did not respond within 5 seconds.")))
                        }
                    }
                    return try JSONDecoder().decode(Firewall.Response.self, from: reply)
                }
            )
        }
    }
}

private final class PendingReply: @unchecked Sendable {

    // NSLock exclusively owns the one-shot continuation. Only the winning callback
    // touches connection teardown. Remove this bridge when XPC gains async replies.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    private let connection: NSXPCConnection
    init(continuation: CheckedContinuation<Data, any Error>, connection: NSXPCConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ result: Result<Data, any Error>) {
        let continuation = lock.withLock {
            let value = self.continuation
            self.continuation = nil
            return value
        }
        guard let continuation else {
            return
        }
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()
        continuation.resume(with: result)
    }
}
