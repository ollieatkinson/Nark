import Control
import Darwin
import Firewall
import Foundation
import Recording
import Synchronization

/// A dedicated CLI consumer; file encoding and flushing run away from the UI actor.
enum RecordingCommand {

    struct Options: Sendable {

        let application: Firewall.Application
        let directory: URL
        init(application: Firewall.Application, output: String?) throws {
            self.application = application
            if let output {
                directory = URL(fileURLWithPath: (output as NSString).expandingTildeInPath).standardizedFileURL
            } else {
                let name = URL(fileURLWithPath: application.path)
                    .deletingPathExtension()
                    .lastPathComponent
                    .map { $0.isLetter || $0.isNumber ? $0 : "-" }
                let stamp = RecordingReport.time(Date()).replacingOccurrences(of: ":", with: "-")
                let support = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                )[0]
                directory = support.appendingPathComponent("Nark/Recordings", isDirectory: true)
                    .appendingPathComponent(
                        "\(String(name.prefix(48)))-\(stamp)-\(UUID().uuidString.prefix(4))",
                        isDirectory: true
                    )
            }
            guard !FileManager.default.fileExists(atPath: directory.path) else {
                throw Firewall.Error.message("Report directory already exists: \(directory.path)")
            }
        }
    }

    private final class StopFlag: Sendable {

        let value = Mutex(false)
        var stopped: Bool {
            value.withLock { $0 }
        }

        func stop() {
            value.withLock { $0 = true }
        }
    }

    @concurrent static func run(client: Firewall.Client, options: Options) async throws {
        let stop = StopFlag()
        var sources: [DispatchSourceSignal] = []
        // SIG_DFL is represented as a nil C function pointer.
        var previous: [(Int32, sig_t?)] = []
        for code in [SIGINT, SIGTERM, SIGHUP] {
            previous.append((code, signal(code, SIG_IGN)))
            let source = DispatchSource.makeSignalSource(
                signal: code,
                queue: .global(qos: .userInitiated)
            )
            source.setEventHandler { stop.stop() }
            source.resume()
            sources.append(source)
        }
        defer {
            for source in sources {
                source.cancel()
            }
            for (code, handler) in previous {
                signal(code, handler)
            }
        }
        let initial = try await client.recording(.start(options.application))
        let journal: RecordingJournal
        do {
            journal = try RecordingJournal(directory: options.directory, initial: initial)
        } catch {
            _ = try? await client.recording(.close(initial.id))
            throw error
        }
        print(
            "Recording \(options.application.path.formatted(.terminalText)) (\(options.application.scope.rawValue))"
        )
        print("Output: \(options.directory.path.formatted(.terminalText))")
        print("Press Ctrl-C to stop and finish the report.")
        fflush(stdout)
        var lastCheckpoint = Date()
        do {
            while !stop.stopped && !Task.isCancelled {
                let batch = try await client.recording(
                    .read(
                        .init(
                            id: initial.id,
                            after: journal.cursor
                        )
                    )
                )
                try journal.append(batch)
                for entry in batch.entries {
                    let c = entry.connection
                    print(
                        "\(RecordingReport.time(entry.time))  \(c.blocked ? "BLOCK" : "ALLOW")  \(c.destination.formatted(.terminalText)):\(c.port.formatted(.terminalText))  \(c.transport.formatted(.terminalText))  \(c.app.formatted(.terminalText))"
                    )
                }
                if batch.dropped > 0 {
                    print(
                        "Recording gap: \(batch.dropped) connections were lost; the report will be marked incomplete."
                    )
                }
                if !batch.entries.isEmpty {
                    fflush(stdout)
                }
                if Date().timeIntervalSince(lastCheckpoint) >= 5 {
                    try journal.checkpoint()
                    lastCheckpoint = Date()
                }
                if !batch.hasMore {
                    try await Task.sleep(for: .milliseconds(200))
                }
            }
            var batch = try await client.recording(
                .stop(
                    .init(
                        id: initial.id,
                        after: journal.cursor
                    )
                )
            )
            while true {
                try journal.append(batch)
                if !batch.hasMore {
                    break
                }
                batch = try await client.recording(
                    .read(
                        .init(
                            id: initial.id,
                            after: journal.cursor
                        )
                    )
                )
            }
            try journal.finish()
            _ = try? await client.recording(.close(initial.id))
            print(
                "\n\(journal.report.observedConnections) connections recorded; \(journal.report.destinations.count) destination endpoints."
            )
            print("Report: \(options.directory.appendingPathComponent("report.md").path.formatted(.terminalText))")
            if journal.report.status == .incomplete {
                throw Firewall.Error.message("Recording completed with gaps. See report.json for details.")
            }
        } catch {
            _ = try? await client.recording(.close(initial.id))
            try? journal.finish(error: error.localizedDescription)
            FileHandle.standardError.write(
                Data("Partial report: \(options.directory.path.formatted(.terminalText))\n".utf8)
            )
            throw error
        }
    }
}

enum ApplicationPath {

    static func resolve(_ path: String) throws -> Firewall.Application {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
            throw Firewall.Error.message("Application or executable does not exist: \(path)")
        }
        if directory.boolValue {
            guard url.pathExtension == "app", Bundle(url: url)?.executableURL != nil else {
                throw Firewall.Error.message("Specify an .app bundle or executable.")
            }
            return try Firewall.Application(path: url.path, scope: .bundle)
        }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw Firewall.Error.message("Not an executable: \(path)")
        }
        return try Firewall.Application(path: url.path, scope: .executable)
    }
}
