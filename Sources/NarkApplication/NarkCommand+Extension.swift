import ArgumentParser

extension NarkCommand {

    struct Activate: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Install the extension and enable filtering.")

        @MainActor func run() async throws {
            try await ExtensionControl.run(.activate)
        }
    }

    struct Disable: AsyncParsableCommand {

        static let configuration =
            CommandConfiguration(abstract: "Disable filtering, retaining the extension and rules.")

        @MainActor func run() async throws {
            try await ExtensionControl.run(.disable)
        }
    }

    struct Deactivate: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Disable filtering and uninstall the extension.")

        @MainActor func run() async throws {
            try await ExtensionControl.run(.deactivate)
        }
    }
}
