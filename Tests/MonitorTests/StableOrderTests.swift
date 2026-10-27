import ComposableArchitecture
import Control
import Firewall
import Foundation
@testable import Monitor
import Testing
import TestSupport

@Suite @MainActor struct StableOrderTests {

    @Test func toggled_rules_keep_display_order_and_selection_when_a_reply_is_reordered(
    ) async throws {
        let runtime = try Firewall.Runtime()
        let first = try Firewall.Rule(domain: "first.test")
        let selected = try Firewall.Rule(domain: "second.test")
        let last = try Firewall.Rule(domain: "third.test")
        var initial = MonitorFeature.State()
        initial.snapshot = Firewall.Snapshot(rules: [first, selected, last])
        initial.rulesVisible = true
        initial.selection = 1
        initial.connected = true
        let store = TestStore(initialState: initial) {
            MonitorFeature(client: .init(runtime: runtime))
        }
        var off = selected
        off.enabled = false
        var reply = Firewall.Snapshot(rules: [off, last, first])
        let expected = Firewall.Snapshot(rules: [first, off, last], startedAt: reply.startedAt)
        await store.send(.received(reply)) { $0.snapshot = expected }
        reply.rules = [last, selected, first]
        var on = expected
        on.rules = [first, selected, last]
        await store.send(.received(reply)) { $0.snapshot = on }
        #expect(store.state.selection == 1)
    }

    @Test func blocklist_values_refresh_in_place_and_new_sources_append() async throws {
        let runtime = try Firewall.Runtime()
        var initial = BlocklistsFeature.State()
        let original = initial.catalog
        initial.selection = original[1].id
        let store = TestStore(initialState: initial) {
            BlocklistsFeature(client: .init(runtime: runtime))
        }
        var updated = original[1]
        updated.enabled = true
        await store.send(.saved([updated, original[0]], selected: nil)) { $0.catalog[1] = updated }
        #expect(store.state.selection == original[1].id)
        #expect(store.state.catalog.map(\.id) == original.map(\.id))
    }
}
