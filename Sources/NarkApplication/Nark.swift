import ArgumentParser
import Control
import Firewall
import Foundation

public enum NarkApplication {

    public static func main() async {
        await NarkCommand.main()
    }
}

struct NarkCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "nark",
        abstract: "Application network activity and blocking.",
        discussion: """
        Requires the signed app bundle and macOS extension approval.
        Direction: ↗ outgoing · ↙ incoming. Incoming connections are observed and allowed.
        Domain rules include subdomains and apply to new outgoing connections.
        """,
        version: version,
        subcommands: [
            Watch.self, Record.self, Status.self, Snapshot.self,
            Rules.self, Block.self, BlockApp.self, Remove.self, Toggle.self, Import.self,
            Blocklists.self, ImportBlocklist.self, ShowBlocklist.self,
            ToggleBlocklist.self, UpdateBlocklist.self, RemoveBlocklist.self,
            ClearHistory.self, Activate.self, Disable.self, Deactivate.self,
        ],
        defaultSubcommand: Watch.self
    )

    private static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unbundled"
        return "Nark \(version) (build \(build))"
    }

    static func client() throws -> Firewall.Client {
        guard
            let service = ExtensionConfiguration.serviceName(),
            let team = Bundle.main.object(forInfoDictionaryKey: "NarkTeamID") as? String
        else {
            throw Firewall.Error.message(
                "Run the signed Nark.app executable in /Applications to connect to the filter."
            )
        }
        return .live(service: service, team: team)
    }

    static func identifier(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw ValidationError("Expected a UUID.")
        }
        return id
    }
}

/// Connects only after Argument Parser has parsed and validated the command.
protocol FilterCommand: AsyncParsableCommand {

    @MainActor func run(client: Firewall.Client) async throws
}

extension FilterCommand {

    @MainActor func run() async throws {
        try await run(client: NarkCommand.client())
    }
}
