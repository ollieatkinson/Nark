import Darwin
import Firewall
import Foundation
import Monitor
import NarkUI
import SwiftTUI
import SwiftTUICLI
import SwiftTUIRuntime

@MainActor
enum Terminal {

    static func run(session: MonitorFeature.Session) async throws {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw Firewall.Error.message("watch requires a terminal; use snapshot for JSON.")
        }
        session.store.send(.start)
        defer { session.store.send(.stop) }
        let configuration = RuntimeConfiguration.builder().companion(.off).build()
        try await TerminalRunner.run(MonitorApp(session: session), configuration: configuration)
    }

    nonisolated static func rulesText(_ rules: [Firewall.Rule]) -> String {
        rules.map {
            "\($0.id)  \($0.enabled ? "on " : "off")  \(($0.domain ?? "*").formatted(.terminalText))  \(($0.app ?? "all apps").formatted(.terminalText))"
        }
        .joined(separator: "\n")
    }
}

private struct MonitorApp: SwiftTUIRuntime.App {

    let session: MonitorFeature.Session?

    nonisolated init() {
        session = nil
    }

    init(session: MonitorFeature.Session) {
        self.session = session
    }

    var body: some Scene {
        WindowGroup("Nark") {
            if let session {
                MonitorDashboard(session: session)
            } else {
                Text("Run nark watch")
            }
        }
    }
}
