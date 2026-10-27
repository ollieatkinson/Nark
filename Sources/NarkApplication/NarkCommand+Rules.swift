import ArgumentParser
import Control
import Firewall
import Foundation

extension NarkCommand {

    struct Rules: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "List manual rules and their IDs.")

        @MainActor func run(client: Firewall.Client) async throws {
            let snapshot = try await client.request(.snapshot)
            print(Terminal.rulesText(snapshot.rules))
        }
    }

    struct Block: FilterCommand {

        static let configuration =
            CommandConfiguration(abstract: "Block a domain or IP, optionally for one executable.")

        @Argument(help: "The domain or IP address to block. Domains include subdomains.")
        var domain: String

        @Option(help: "Restrict the rule to an absolute executable path.", completion: .file())
        var app: String?

        func validate() throws {
            do {
                _ = try Firewall.Rule(app: app, domain: domain)
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }

        @MainActor func run(client: Firewall.Client) async throws {
            let rule = try Firewall.Rule(app: app, domain: domain)
            let snapshot = try await client.request(.add(rule))
            print(Terminal.rulesText(snapshot.rules))
        }
    }

    struct BlockApp: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Block an executable's new outgoing connections.")

        @Argument(help: "The absolute executable path to block.", completion: .file())
        var path: String

        func validate() throws {
            do {
                _ = try Firewall.Rule(app: path)
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }

        @MainActor func run(client: Firewall.Client) async throws {
            let snapshot = try await client.request(.add(Firewall.Rule(app: path)))
            print(Terminal.rulesText(snapshot.rules))
        }
    }

    struct Remove: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Remove a manual rule.")

        @Argument(help: "The rule UUID.", transform: NarkCommand.identifier)
        var id: UUID

        @MainActor func run(client: Firewall.Client) async throws {
            let snapshot = try await client.request(.remove(id))
            print(Terminal.rulesText(snapshot.rules))
        }
    }

    struct Toggle: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Enable or disable a manual rule.")

        @Argument(help: "The rule UUID.", transform: NarkCommand.identifier)
        var id: UUID

        @MainActor func run(client: Firewall.Client) async throws {
            let snapshot = try await client.request(.toggle(id))
            print(Terminal.rulesText(snapshot.rules))
        }
    }

    struct Import: FilterCommand {

        static let configuration = CommandConfiguration(abstract: "Import a domain or hosts file as manual rules.")

        @Argument(help: "The UTF-8 domain or hosts file to import.", completion: .file())
        var file: String

        @MainActor func run(client: Firewall.Client) async throws {
            let snapshot = try await client.request(.importDomains(DomainList.read(file)))
            print("\(snapshot.rules.count) rules")
        }
    }
}
