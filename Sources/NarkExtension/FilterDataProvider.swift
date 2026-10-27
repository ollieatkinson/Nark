import Control
import Firewall
import Foundation
import Network
import NetworkExtension
import os
import Security
import Synchronization
import Vocabulary

@objc(FilterDataProvider)
final class FilterDataProvider: NEFilterDataProvider, NSXPCListenerDelegate, @unchecked Sendable {

    // Foundation delegates are not Sendable. Mutable provider state is guarded by
    // lifecycle or inspections; extracted runtimes own state through Mutex.
    // Remove unchecked conformance when NetworkExtension supplies checked isolation.
    private struct State {

        var engine: Firewall.Runtime?
        var listener: NSXPCListener?
        var timer: DispatchSourceTimer?
    }

    private let lifecycle = NSLock()
    private var state = State()

    // NEFilterSocketFlow is not Sendable in the SDK. The reference is immutable,
    // and is used outside callbacks only for update(_:using:for:), an API explicitly
    // supporting that use. Mutable inspection state stays under inspections' Mutex.
    // Remove unchecked conformance when the SDK annotates flow sendability.
    private struct Pending: @unchecked Sendable {

        let flow: NEFilterSocketFlow
        var connection: Firewall.Connection
        var session: Firewall.Hostname.Inspection.Session
        let started = ContinuousClock.now
    }

    // At most 256 bounded handshake buffers; idle attempts expire after five seconds.
    // Callbacks are synchronous, so Mutex owns this state without an async hop.
    private let inspections = Mutex<[UUID: Pending]>([:])
    // Preserve the SDK's NSUInteger all-bytes sentinel through its Int API import.
    private static let allFlowBytes = Int(truncatingIfNeeded: NEFilterFlowBytesMax)
    private var engine: Firewall.Runtime? {
        lifecycle.withLock { state.engine }
    }

    private let logger = Logger(subsystem: ExtensionConfiguration.extensionID, category: "provider")

    override func startFilter(completionHandler: @escaping @Sendable (Error?) -> Void) {
        do {
            guard
                let group = Bundle.main.object(forInfoDictionaryKey: "NarkAppGroup") as? String,
                let directory = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: group
                ),
                let service = ExtensionConfiguration.serviceName()
            else {
                throw Firewall.Error.message("Missing app group or Mach service configuration.")
            }
            let engine = try Firewall.Runtime(
                directory: directory.appendingPathComponent("Nark", isDirectory: true),
                onHistoryFailure: { error in
                    logger
                        .error(
                            "Activity restore failed: \(String(describing: error), privacy: .public)"
                        )
                }
            )
            let restored = engine.snapshot()
            logger
                .info(
                    "Loaded \(restored.rules.count) rules and \(restored.rows.count) destinations from \(directory.path, privacy: .public)"
                )
            let listener = NSXPCListener(machServiceName: service)
            listener.delegate = self
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self, engine] in
                self?.expireInspections(engine: engine)
                do {
                    try engine.checkpoint()
                    self?.logger
                        .debug(
                            "Activity checkpoint saved: \(engine.snapshot().rows.count) destinations"
                        )
                } catch {
                    self?.logger.error("Activity checkpoint failed: \(error.localizedDescription)")
                }
            }
            lifecycle.withLock { state = State(engine: engine, listener: listener, timer: timer) }
            listener.resume()
            timer.resume()
            apply(NEFilterSettings(rules: [], defaultAction: .filterData)) {
                [weak self, engine] error in
                if let error {
                    _ = try? engine.events.send(
                        Event(nark.filter.lifecycle.fail.reason[error.localizedDescription])
                    )
                    self?.teardown()
                } else {
                    _ = try? engine.events.send(Event(nark.filter.lifecycle.start))
                }
                completionHandler(error)
            }
        } catch { completionHandler(error) }
    }

    override func stopFilter(
        with reason: NEProviderStopReason, completionHandler: @escaping () -> Void
    ) {
        teardown()
        completionHandler()
    }

    private func teardown() {
        let previous = lifecycle.withLock {
            let previous = state
            state = State()
            return previous
        }
        previous.timer?.cancel()
        if let engine = previous.engine {
            let unfinished = inspections.withLock { pending in
                defer { pending.removeAll() }
                return pending.values.map(\.connection)
            }
            for connection in unfinished {
                _ = engine.evaluate(connection)
            }
            _ = try? engine.events.send(Event(nark.filter.lifecycle.stop))
        }
        try? previous.engine?.checkpoint()
        previous.listener?.invalidate()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard
            let engine,
            let team = Bundle.main.object(forInfoDictionaryKey: "NarkTeamID") as? String,
            !team.isEmpty
        else {
            return false
        }
        connection.setCodeSigningRequirement(
            "anchor apple generic and identifier \"\(ExtensionConfiguration.appID)\" and certificate leaf[subject.OU] = \"\(team)\""
        )
        connection.exportedInterface = NSXPCInterface(with: FirewallService.self)
        connection.exportedObject = FilterService(engine: engine)
        connection.resume()
        return true
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socket = flow as? NEFilterSocketFlow, let engine
        else {
            return .allow()
        }
        let row = describe(socket)
        if row.direction != .outbound {
            _ = engine.evaluate(row)
            return reporting(.allow())
        }
        if engine.isBlocked(app: row.app, host: row.host, address: row.address) {
            return reporting(engine.evaluate(row).verdict == .drop ? .drop() : .allow())
        }
        let transport: Firewall.Hostname.Inspection.Session.Transport? =
            socket.socketProtocol == IPPROTO_TCP
                ? .tcp
                : socket.socketProtocol == IPPROTO_UDP && ["443", "853"]
                    .contains(row.port) ? .quic : nil
        if row.host == nil, let transport {
            let admitted = inspections.withLock { pending in
                guard pending.count < 256 else {
                    return false
                }
                pending[row.id] = Pending(flow: socket, connection: row, session: .init(transport))
                return true
            }
            guard admitted
            else {
                return reporting(engine.evaluate(row).verdict == .drop ? .drop() : .allow())
            }
            return reporting(.filterDataVerdict(
                withFilterInbound: false, peekInboundBytes: 0, filterOutbound: true,
                peekOutboundBytes: Self.allFlowBytes
            ))
        }
        return reporting(engine.evaluate(row).verdict == .drop ? .drop() : .allow())
    }

    override func handleOutboundData(
        from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data
    ) -> NEFilterDataVerdict {
        guard
            let socket = flow as? NEFilterSocketFlow, flow.direction == .outbound,
            let engine
        else {
            return .allow()
        }
        let outcome: (Firewall.Connection, Firewall.Hostname.Inspection.Result)? = inspections
            .withLock { pending in
                guard var attempt = pending.removeValue(forKey: flow.identifier) else {
                    return nil
                }
                let result = attempt.started.duration(to: .now) >= .seconds(5)
                    ? .unavailable
                    : attempt.session.inspect(readBytes, at: offset)
                if result == .needMore {
                    pending[flow.identifier] = attempt
                }
                if case .hostname(let host) = result {
                    attempt.connection.host = host
                }
                return (attempt.connection, result)
            }
        // A timed-out attempt has already been evaluated by the expiry timer.
        guard let (row, result) = outcome else {
            return reporting(.allow())
        }
        if result == .needMore {
            // TCP retains its prefix until a verdict. Pass each UDP datagram so a
            // fragmented QUIC handshake can progress; inspect the next Initial.
            return reporting(NEFilterDataVerdict(
                passBytes: socket.socketProtocol == IPPROTO_UDP
                    ? readBytes.count
                    : 0,
                peekBytes: Self.allFlowBytes
            ))
        }
        return reporting(engine.evaluate(row).verdict == .drop ? .drop() : .allow())
    }

    override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        if
            let engine,
            let pending = inspections.withLock({ $0.removeValue(forKey: flow.identifier) })
        {
            return reporting(engine.evaluate(pending.connection)
                .verdict == .drop ? .drop() : .allow())
        }
        return .allow()
    }

    override func handle(_ report: NEFilterReport) {
        guard
            report.event == .statistics || report.event == .flowClosed,
            let flow = report.flow
        else {
            return
        }
        if
            report.event == .flowClosed,
            let pending = inspections.withLock({ $0.removeValue(forKey: flow.identifier) })
        {
            _ = engine?.evaluate(pending.connection)
        }
        engine?.reportTraffic(
            id: flow.identifier,
            received: Int64(report.bytesInboundCount),
            sent: Int64(report.bytesOutboundCount),
            closed: report.event == .flowClosed
        )
    }

    private func expireInspections(engine: Firewall.Runtime) {
        let expired = inspections.withLock { pending in
            let expired = pending.filter { $0.value.started.duration(to: .now) >= .seconds(5) }
            for id in expired.keys {
                pending.removeValue(forKey: id)
            }
            return Array(expired.values)
        }
        for attempt in expired {
            let decision = engine.evaluate(attempt.connection)
            update(
                attempt.flow,
                using: reporting(decision.verdict == .drop ? .drop() : .allow()),
                for: .outbound
            )
        }
    }

    private func reporting(_ verdict: NEFilterNewFlowVerdict) -> NEFilterNewFlowVerdict {
        verdict.shouldReport = true
        verdict.statisticsReportFrequency = .medium
        return verdict
    }

    private func reporting(_ verdict: NEFilterDataVerdict) -> NEFilterDataVerdict {
        verdict.shouldReport = true
        verdict.statisticsReportFrequency = .medium
        return verdict
    }

    private func describe(_ flow: NEFilterSocketFlow) -> Firewall.Connection {
        var address = "unknown"
        var port = "?"
        if case .hostPort(let host, let remotePort) = flow.remoteFlowEndpoint {
            address = "\(host)"
            port = "\(remotePort.rawValue)"
        }
        var localAddress: String?
        var localPort: String?
        if case .hostPort(let host, let port) = flow.localFlowEndpoint {
            localAddress = "\(host)"
            localPort = "\(port.rawValue)"
        }
        let direction: Firewall.Direction = switch flow.direction {
            case .inbound:
                .inbound
            case .outbound:
                .outbound
            default:
                .unknown
        }
        return Firewall.Connection(
            id: flow.identifier,
            app: Self.appPath(token: flow.sourceAppAuditToken),
            host: (flow.remoteHostname ?? flow.url?.host).flatMap(Firewall.Hostname.normalize),
            address: address, port: port,
            transport: flow.socketProtocol == IPPROTO_TCP
                ? "TCP"
                : flow.socketProtocol == IPPROTO_UDP ? "UDP" : "IP", blocked: false,
            direction: direction, localAddress: localAddress, localPort: localPort
        )
    }

    private static func appPath(token: Data?) -> String {
        guard let token else {
            return "unknown"
        }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: token] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code
        else {
            return "unknown"
        }
        var staticCode: SecStaticCode?
        guard
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            let executable = executablePath(for: staticCode)
        else {
            return "unknown"
        }
        return executable
    }

    private static func executablePath(for code: SecStaticCode) -> String? {
        // SecCodeCopyPath can return a bundle root. Rules target the actual executable.
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
            let dictionary = information as? [String: Any],
            let url = dictionary[kSecCodeInfoMainExecutable as String] as? URL
        else {
            return nil
        }
        return url.path
    }
}

private final class FilterService: NSObject, FirewallService {

    let engine: Firewall.Runtime
    init(engine: Firewall.Runtime) {
        self.engine = engine
    }

    func request(_ payload: Data, reply: @escaping (Data) -> Void) {
        let result: Firewall.Response
        do {
            guard payload.count <= 24_000_000 else {
                throw Firewall.Error.message("Request exceeds size limit.")
            }
            result = engine.handle(try JSONDecoder().decode(Message.self, from: payload).request())
        } catch { result = Firewall.Response(error: error.localizedDescription) }
        reply((try? JSONEncoder().encode(result)) ?? Data())
    }
}
