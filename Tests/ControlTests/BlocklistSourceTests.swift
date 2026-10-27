import Control
import Foundation
import Testing

@Test func file_sources_are_bounded_utf8_and_reject_unsupported_rule_syntax() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("0.0.0.0 ads.test\ntracker.test".utf8).write(to: file)
    let input = try await BlocklistSource.read(file.path)
    #expect(input.source == file.path)
    #expect(input.enable == nil)
    for data in [
        Data([0xff, 0xfe]),
        Data("||ads.test^$third-party".utf8),
        Data(repeating: 97, count: BlocklistSource.limit + 1)
    ] {
        try data.write(to: file)
        await #expect(throws: (any Error).self) { try await BlocklistSource.read(file.path) }
    }
}
