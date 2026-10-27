import ArgumentParser
import Control
import Firewall
import Foundation

extension NarkCommand {

    struct Blocklists: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "List named blocklists and their state.")

        @MainActor func run(client: Firewall.Client) async throws {
            let lists = try await client.request(.snapshot).blocklists ?? []
            for list in lists {
                print(
                    "\(list.id)  \(list.enabled ? "on " : "off")  \(list.domainCount) domains  \(list.name.formatted(.terminalText))"
                )
            }
        }
    }

    struct ImportBlocklist: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Import a named blocklist, initially disabled.")

        @Argument(help: "An HTTPS URL or local UTF-8 domain or hosts file.", completion: .file())
        var source: String

        @MainActor func run(client: Firewall.Client) async throws {
            let input = try await BlocklistSource.read(source)
            let snapshot = try await client.request(.blocklist(.replace(input)))
            if let list = snapshot.blocklists?.first(where: { $0.source == input.source }) {
                print(
                    "\(list.id)  \(list.domainCount) domains  \(list.enabled ? "on" : "off")  \(list.name.formatted(.terminalText))"
                )
            }
        }
    }

    struct ShowBlocklist: FilterCommand {

        static let configuration =
            CommandConfiguration(abstract: "Inspect a blocklist's domains, source and attribution.")

        @Argument(help: "The blocklist UUID.", transform: NarkCommand.identifier)
        var id: UUID

        @MainActor func run(client: Firewall.Client) async throws {
            let list = try await client.blocklist(id)
            print(
                "\(list.summary.name.formatted(.terminalText)) · \(list.summary.enabled ? "on" : "off") · \(list.domains.count) domains"
            )
            print(list.summary.source.formatted(.terminalText))
            print(list.summary.attribution.formatted(.terminalText))
            for domain in list.domains {
                print(domain.formatted(.terminalText))
            }
        }
    }

    struct ToggleBlocklist: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Enable or disable a cached blocklist.")

        @Argument(help: "The blocklist UUID.", transform: NarkCommand.identifier)
        var id: UUID

        @MainActor func run(client: Firewall.Client) async throws {
            _ = try await client.request(.blocklist(.toggle(id)))
            print("Blocklist toggled.")
        }
    }

    struct UpdateBlocklist: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Refresh a blocklist, retaining its enabled state.")

        @Argument(help: "The blocklist UUID.", transform: NarkCommand.identifier)
        var id: UUID

        @MainActor func run(client: Firewall.Client) async throws {
            let list = try await client.blocklist(id)
            var input = try await BlocklistSource.read(list.summary.source)
            input.id = id
            _ = try await client.request(.blocklist(.replace(input)))
            print("Blocklist updated.")
        }
    }

    struct RemoveBlocklist: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Remove a named blocklist.")

        @Argument(help: "The blocklist UUID.", transform: NarkCommand.identifier)
        var id: UUID

        @MainActor func run(client: Firewall.Client) async throws {
            _ = try await client.request(.blocklist(.remove(id)))
            print("Blocklist removed.")
        }
    }
}
