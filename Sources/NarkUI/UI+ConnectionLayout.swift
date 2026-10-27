import Firewall
import Foundation
import SwiftTUI

extension UI {

    /// One width contract for a connection table's heading and visible rows.
    @MainActor public struct ConnectionLayout: Sendable {

        private let width: Int
        private let showsEndpoint: Bool
        public init(width: Int, showsEndpoint: Bool) {
            self.width = width
            self.showsEndpoint = showsEndpoint
        }

        public var header: TextRow {
            make(
                app: "APPLICATION",
                destination: "REMOTE",
                endpoint: "ADDRESS / PORT",
                transport: "TYPE",
                direction: "DIR",
                count: "FLOWS",
                policy: "POLICY",
                header: true
            )
        }

        public func row(_ connection: Firewall.Connection, policyBlocks: Bool) -> TextRow {
            let label = "\(connection.direction.name), \(connection.destination.formatted(.terminalText)), port \(connection.port.formatted(.terminalText)), \(connection.transport.formatted(.terminalText)), \(connection.count) flows, \(policyBlocks ? "blocked" : "allowed")"
            return make(
                app: URL(fileURLWithPath: connection.app).lastPathComponent,
                destination: connection.destination,
                endpoint: (connection.address.contains(":")
                    ? "[\(connection.address)]"
                    : connection.address) + ":" + connection.port,
                transport: connection.transport,
                direction: UI.directionSymbol([connection.direction]),
                count: "\(connection.count)",
                policy: policyBlocks ? "BLOCK" : "ALLOW",
                header: false,
                label: label,
                directionStyle: UI.directionStyle([connection.direction])
            )
        }

        private func make(
            app: String,
            destination: String,
            endpoint: String,
            transport: String,
            direction: String,
            count: String,
            policy: String,
            header: Bool,
            label: String? = nil,
            directionStyle: ThemeShapeStyle? = nil
        ) -> TextRow {
            let appWidth = max(12, min(24, width / 6))
            let endpointWidth = showsEndpoint ? max(20, min(34, width / 4)) : 0
            let nameWidth = max(1, width - appWidth - endpointWidth - 20 - (showsEndpoint ? 6 : 5))
            let muted: ThemeShapeStyle? = header ? .theme.muted : nil
            return TextRow(
                [
                    .init(app, width: appWidth, style: muted),
                    .init(
                        destination,
                        width: nameWidth,
                        style: muted
                    ),
                ] + (showsEndpoint ? [.init(endpoint, width: endpointWidth, style: muted)] : []) + [
                    .init(transport, width: 4, style: muted),
                    .init(
                        direction,
                        width: 3,
                        style: directionStyle ?? .theme.muted
                    ),
                    .init(count, width: 7, alignment: .trailing, style: muted),
                    .init(
                        policy,
                        width: 6,
                        alignment: .trailing,
                        style: header ? .theme.muted : policy == "BLOCK" ? .theme.danger : .theme.success
                    ),
                ],
                leadingPadding: header ? 2 : 0,
                accessibilityLabel: label
            )
        }
    }
}
