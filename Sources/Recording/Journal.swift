import Darwin
import Firewall
import Foundation

/// Append-only JSON Lines plus periodically refreshed human and machine-readable summaries.
public final class RecordingJournal {

    private struct Line: Encodable {

        enum Kind: String, Encodable {
            case started
            case connection
            case gap
            case ended
            case error
        }

        let kind: Kind
        let recording: UUID
        let time: Date
        var application: Firewall.Application?
        var entry: Firewall.Recording.Entry?
        var missing: UInt64?
        var message: String?
    }

    public let directory: URL
    private let handle: FileHandle
    private let encoder: JSONEncoder
    private var summary: RecordingSummary
    private let id: UUID
    private var closed = false

    public init(directory: URL, initial: Firewall.Recording.Batch) throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw Firewall.Error.message("Report directory already exists: \(directory.path)")
        }
        try FileManager.default.createDirectory(
            at: directory.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard mkdir(directory.path, 0o700) == 0 else {
            if errno == EEXIST {
                throw Firewall.Error.message("Report directory already exists: \(directory.path)")
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let log = directory.appendingPathComponent("connections.jsonl")
        guard FileManager.default.createFile(
            atPath: log.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw Firewall.Error.message("Cannot create connection log.")
        }
        handle = try FileHandle(forWritingTo: log)
        self.directory = directory
        id = initial.id
        summary = RecordingSummary(initial)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(RecordingReport.time(date))
        }
        try write(
            Line(
                kind: .started,
                recording: id,
                time: initial.startedAt,
                application: initial.application
            )
        )
        try handle.synchronize()
        try checkpoint()
    }

    deinit { try? handle.close() }
    public var report: RecordingReport {
        summary.report
    }

    public var cursor: UInt64 {
        summary.cursor
    }

    public func append(_ batch: Firewall.Recording.Batch) throws {
        guard !closed else {
            throw Firewall.Error.message("Recording log is closed.")
        }
        var next = summary
        try next.append(batch)
        if batch.dropped > 0 {
            try write(
                Line(
                    kind: .gap,
                    recording: id,
                    time: batch.entries.first?.time ?? Date(),
                    missing: batch.dropped
                )
            )
        }
        for entry in batch.entries {
            try write(Line(kind: .connection, recording: id, time: entry.time, entry: entry))
        }
        try handle.synchronize()
        summary = next
    }

    public func finish(error: String? = nil) throws {
        guard !closed else {
            return
        }
        if let error {
            summary.fail(error)
            try write(Line(kind: .error, recording: id, time: Date(), message: error))
        }
        try write(Line(kind: .ended, recording: id, time: report.endedAt ?? Date()))
        try handle.synchronize()
        try checkpoint()
        try handle.close()
        closed = true
    }

    public func checkpoint() throws {
        try save(encoder.encode(report), to: "report.json")
        try save(Data(report.markdown().utf8), to: "report.md")
    }

    private func write(_ line: Line) throws {
        var data = try encoder.encode(line)
        data.append(0x0a)
        try handle.write(contentsOf: data)
    }

    private func save(_ data: Data, to name: String) throws {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
