import ArgumentParser
import Control
import Firewall
import Foundation
import Monitor

extension NarkCommand {

    struct Watch: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Open the interactive network monitor.")

        @Option(
            help: "Focus on an .app bundle, including nested helpers, or an executable path.",
            completion: .file(),
            transform: ApplicationPath.resolve
        )
        var app: Firewall.Application?

        @MainActor func run(client: Firewall.Client) async throws {
            let session = MonitorFeature.Session(client: client, application: app)
            try await Terminal.run(session: session)
        }
    }

    struct Record: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Log an application's new connections until Ctrl-C and write reports.",
            discussion: """
            APP accepts an .app bundle (including nested helpers) or an executable path.
            Recording continues across application restarts until you stop it.
            Writes connections.jsonl, report.md and report.json to a new directory.
            Earlier activity and existing open connections are not backfilled.
            """
        )

        @Argument(
            help: "The application or executable to record.",
            completion: .file(),
            transform: ApplicationPath.resolve
        )
        var application: Firewall.Application?

        @Option(
            help: "The application to record, as an alternative to the APP argument.",
            completion: .file(),
            transform: ApplicationPath.resolve
        )
        var app: Firewall.Application?

        @Option(
            help: "A new report directory. Defaults to a timestamped directory in Application Support.",
            completion: .directory
        )
        var output: String?

        func validate() throws {
            guard (application == nil) != (app == nil) else {
                throw ValidationError("Specify one application, as APP or --app APP.")
            }
        }

        func run() async throws {
            guard let application = application ?? app else {
                throw ValidationError("Specify an application to record.")
            }
            let options = try RecordingCommand.Options(application: application, output: output)
            try await RecordingCommand.run(client: NarkCommand.client(), options: options)
        }
    }

    struct Status: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Show connection counts and rule totals.")

        @MainActor func run(client: Firewall.Client) async throws {
            let snapshot = try await client.request(.snapshot)
            print(
                "\(snapshot.rows.count) destinations; \(snapshot.totalAllowed) allowed, \(snapshot.totalBlocked) blocked; \(snapshot.rules.count) rules"
            )
        }
    }

    struct Snapshot: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Print network activity and policy as JSON.")

        @MainActor func run(client: Firewall.Client) async throws {
            let snapshot = try await client.request(.snapshot)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
        }
    }

    struct ClearHistory: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Erase recorded activity.")

        @MainActor func run(client: Firewall.Client) async throws {
            _ = try await client.request(.clearHistory)
            print("Activity history cleared.")
        }
    }
}
