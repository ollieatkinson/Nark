@testable import Firewall
import Foundation
import Testing

@Suite struct RecordingRuntimeTests {

    func connection(_ app: String, host: String = "example.test") -> Firewall.Connection {
        .init(
            app: app,
            host: host,
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
    }

    @Test func application_scope_has_bundle_boundaries_and_exact_executable_matching() throws {
        let app = try Firewall.Application(path: "/Applications/Example.app", scope: .bundle)
        #expect(app.matches("/Applications/Example.app/Contents/MacOS/Example"))
        #expect(app.matches("/Applications/Example.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"))
        #expect(!app.matches("/Applications/Example.app.other/Contents/MacOS/Example"))
        let exe = try Firewall.Application(path: "/usr/bin/curl", scope: .executable)
        #expect(exe.matches("/usr/bin/curl"))
        #expect(!exe.matches("/usr/bin/curl-helper"))
        #expect(throws: (any Error).self) { try Firewall.Application(path: "/", scope: .executable)
        }
        #expect(throws: (any Error).self) {
            try Firewall.Application(
                path: "relative",
                scope: .bundle
            )
        }
    }

    @Test func scope_matches_foundation_and_security_spellings_of_private_paths() throws {
        let bundle = try Firewall.Application(path: "/private/tmp/Fixture.app", scope: .bundle)
        #expect(bundle.matches("/private/tmp/Fixture.app/Contents/MacOS/Main"))
        #expect(bundle.matches("/tmp/Fixture.app/Contents/Helpers/Helper"))
        #expect(!bundle.matches("/private/tmp/Fixture.app.other/Contents/MacOS/Main"))
        let executable = try Firewall.Application(path: "/private/tmp/Main", scope: .executable)
        #expect(executable.matches("/private/tmp/Main"))
        #expect(executable.matches("/tmp/Main"))
    }

    @Test func recording_starts_fresh_includes_helpers_and_freezes_on_stop() throws {
        let runtime = try Firewall.Runtime()
        let app = try Firewall.Application(path: "/Applications/Example.app", scope: .bundle)
        let main = connection(app.path + "/Contents/MacOS/Example")
        runtime.record(main)
        let start = try runtime.recording(.start(app))
        #expect(start.entries.isEmpty)
        #expect(try runtime.recording(.read(.init(id: start.id, after: 0))).entries.isEmpty)
        runtime.record(main)
        runtime.record(connection(app.path + "/Contents/Helpers/Helper", host: "helper.test"))
        runtime.record(connection("/Applications/Other.app/Contents/MacOS/Other"))
        let stopped = try runtime.recording(.stop(.init(id: start.id, after: 0)))
        #expect(stopped.entries.count == 2)
        #expect(stopped.entries.map(\.sequence) == [1, 2])
        #expect(stopped.endedAt != nil)
        runtime.record(main)
        #expect(try runtime.recording(.read(.init(id: start.id, after: 2))).lastSequence == 2)
        #expect(runtime.snapshot().totalAllowed == 5)
        _ = try runtime.recording(.close(start.id))
        #expect(throws: (any Error).self) {
            try runtime.recording(
                .read(
                    .init(
                        id: start.id,
                        after: 2
                    )
                )
            )
        }
    }

    @Test func overflow_reports_exact_gaps_and_drains_ordered_pages() throws {
        let runtime = try Firewall.Runtime()
        let app = try Firewall.Application(path: "/usr/bin/curl", scope: .executable)
        let start = try runtime.recording(.start(app))
        let total = Firewall.Recording.Session.capacity + 17
        for _ in 0 ..< total {
            runtime.record(connection(app.path))
        }
        var cursor: UInt64 = 0
        var sequences: [UInt64] = []
        var lost: UInt64 = 0
        while true {
            let batch = try runtime.recording(.read(.init(id: start.id, after: cursor)))
            lost += batch.dropped
            sequences += batch.entries.map(\.sequence)
            cursor = batch.cursor
            #expect(batch.entries.count <= Firewall.Recording.Session.batchSize)
            if !batch.hasMore {
                break
            }
        }
        #expect(lost == 17)
        #expect(sequences == Array(UInt64(18) ... UInt64(total)))
        #expect(throws: (any Error).self) {
            try runtime.recording(
                .read(
                    .init(
                        id: start.id,
                        after: .max
                    )
                )
            )
        }
    }

    @Test func independent_recordings_survive_global_history_clear_and_have_bounded_leases() throws {
        let runtime = try Firewall.Runtime()
        let a = try Firewall.Application(path: "/a", scope: .executable)
        let b = try Firewall.Application(path: "/b", scope: .executable)
        let sa = try runtime.recording(.start(a))
        let sb = try runtime.recording(.start(b))
        runtime.record(connection(a.path))
        runtime.record(connection(b.path))
        #expect(runtime.handle(.clearHistory).error == nil)
        #expect(try runtime.recording(.read(.init(id: sa.id, after: 0))).entries.map(\.connection.app) == [a.path])
        #expect(try runtime.recording(.read(.init(id: sb.id, after: 0))).entries.map(\.connection.app) == [b.path])
        for _ in 0 ..< 6 {
            _ = try runtime.recording(.start(a))
        }
        #expect(throws: (any Error).self) { try runtime.recording(.start(a)) }
        _ = try runtime.recording(.close(sa.id))
        _ = try runtime.recording(.start(a))
        let old = Firewall.Recording.Session(application: a, now: Date(timeIntervalSince1970: 0))
        #expect(old.expired(at: Date(timeIntervalSince1970: 61)))
    }
}
