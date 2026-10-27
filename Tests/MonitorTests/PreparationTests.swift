import ComposableArchitecture
import Control
import Firewall
@testable import Monitor
import Testing

@Suite @MainActor struct PreparationTests {

    @Test func a_refresh_reorders_the_selected_row_without_resetting_its_acknowledgement() async {
        let first = connection("first.test")
        let selected = connection("second.test")
        var state = MonitorFeature.State()
        state.snapshot = .init(rows: [first, selected])
        state.page = .activity
        state.selection = 1
        state.selectionEvent = 42
        let snapshot = Firewall.Snapshot(rows: [selected, first])
        let store = TestStore(initialState: state) {
            MonitorFeature(client: .init { _ in snapshot })
        }
        await store.send(.received(snapshot)) {
            $0.snapshot = snapshot
            $0.selection = 0
            $0.selectionEvent = 42
            $0.connected = true
        }
        #expect(store.state.selectedConnection?.id == selected.id)
    }

    @Test func a_prepared_snapshot_and_its_filtered_indices_are_installed_together() async {
        let snapshot = Firewall.Snapshot(rows: [connection("keep.test"), connection("other.test")])
        var state = MonitorFeature.State()
        state.query = "keep"
        let store = TestStore(initialState: state) {
            MonitorFeature(client: .init { _ in snapshot })
        }
        await store.send(.prepareSnapshot(snapshot)) { $0.busy = true }
        await store.receive(\.received) {
            $0.snapshot = snapshot
            $0.connected = true
            $0.busy = false
        }
        #expect(store.state.snapshot.rows.count == 2)
        #expect(store.state.matchingRows.map(\.host) == ["keep.test"])
        #expect(store.state.content.snapshot == store.state.snapshot)
    }

    @Test func an_outdated_preparation_retries_with_the_current_filter() async {
        let snapshot = Firewall.Snapshot(rows: [connection("keep.test"), connection("other.test")])
        var state = MonitorFeature.State()
        state.query = "other"
        let preparation = MonitorFeature.Content.Preparation(snapshot: snapshot, state: state)
        let content = await preparation.content()
        state.query = "keep"
        let previous = state.snapshot
        let store = TestStore(initialState: state) {
            MonitorFeature(client: .init { _ in snapshot })
        }
        await store.send(.received(content.snapshot, content: content, revision: preparation.revision)) {
            $0.busy = true
        }
        #expect(store.state.snapshot == previous)
        await store.receive(\.received) {
            $0.snapshot = snapshot
            $0.connected = true
            $0.busy = false
        }
        #expect(store.state.query == "keep")
        #expect(store.state.matchingRows.map(\.host) == ["keep.test"])
    }

    private func connection(_ host: String) -> Firewall.Connection {
        .init(
            app: "/Applications/Example.app/Contents/MacOS/Example",
            host: host,
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false
        )
    }
}
