import ComposableArchitecture
import Control
import Firewall
import Foundation
@testable import Monitor
import Testing
import TestSupport

@Suite @MainActor struct BlocklistsTests {

    @Test func enabling_an_unloaded_preset_fetches_and_commits_as_one_operation() async throws {
        let runtime = try Firewall.Runtime()
        let preset = Firewall.Blocklist.presets[0].summary
        let store = TestStore(initialState: BlocklistsFeature.State()) {
            BlocklistsFeature(client: .init(runtime: runtime), load: { source in
                #expect(source == preset.source)
                return .init(name: preset.name, source: source, text: "ads.test")
            })
        }
        await store.send(.toggle) { $0.busy = true }
        await store.receive(\.fetched)
        await store.receive(\.saved) {
            $0.busy = false
            $0.catalog = runtime.snapshot().blocklists!
        }
        #expect(runtime.isBlocked(app: "/app", host: "ads.test", address: "192.0.2.1"))
        await store.send(.toggle) { $0.busy = true }
        await store.receive(\.saved) { $0.busy = false
            $0.catalog = runtime.snapshot().blocklists!
        }
        #expect(!runtime.isBlocked(app: "/app", host: "ads.test", address: "192.0.2.1"))
    }

    @Test func download_failure_keeps_existing_enabled_list() async throws {
        let runtime = try Firewall.Runtime()
        let preset = Firewall.Blocklist.presets[0].summary
        _ = runtime.handle(.blocklist(.replace(.init(
            id: preset.id,
            name: preset.name,
            source: preset.source,
            text: "ads.test",
            enable: true
        ))))
        var initial = BlocklistsFeature.State()
        initial.catalog = runtime.snapshot().blocklists!
        let store = TestStore(initialState: initial) {
            BlocklistsFeature(
                client: .init(runtime: runtime),
                load: { _ in throw Firewall.Error.message("Download failed") }
            )
        }
        await store.send(.refresh) { $0.busy = true }
        await store.receive(\.failed) { $0.busy = false
            $0.error = "Download failed"
        }
        #expect(runtime.isBlocked(app: "/app", host: "ads.test", address: "192.0.2.1"))
    }
}

extension BlocklistsTests {

    @Test func community_categories_filter_and_adding_a_source_keeps_it_off() async throws {
        let runtime = try Firewall.Runtime()
        let preset = Firewall.Blocklist.community.first { $0.name == "1Hosts Lite" }!
        var initial = BlocklistsFeature.State()
        initial.communityVisible = true
        let store = TestStore(initialState: initial) {
            BlocklistsFeature(
                client: .init(runtime: runtime),
                load: { _ in .init(name: preset.name, source: preset.source, text: "ads.test") }
            )
        }
        await store.send(.addCommunity(preset.id)) { $0.busy = true }
        await store.receive(\.fetched)
        await store.receive(\.saved) {
            $0.busy = false
            $0.communityVisible = false
            $0.selection = preset.id
            $0.catalog = runtime.snapshot().blocklists!
        }
        #expect(!runtime.isBlocked(app: "/app", host: "ads.test", address: "192.0.2.1"))
        var state = BlocklistsFeature.State()
        state.category = .explicit
        #expect(state.community.map(\.name) == ["OISD NSFW Small"])
        state.category = .security
        #expect(Set(state.community.map(\.name)) == ["1Hosts Lite", "Anudeep"])
    }
}
