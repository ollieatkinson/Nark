import Control
import Firewall
import Foundation
import Monitor
@testable import NarkApplication
import SwiftTUI
import Testing

@Suite @MainActor struct NavigationPerformanceTests {

    @Test func navigation_frames_with_two_thousand_connections() throws {
        let runtime = try Firewall.Runtime()
        let session = MonitorFeature.Session(client: .init(runtime: runtime))
        let rows = (0 ..< 2000).map { index in
            Firewall.Connection(
                app: "/Applications/App\(index % 80).app/Contents/MacOS/App",
                host: "host-\(index).test",
                address: index.isMultiple(of: 2) ? "192.0.2.1" : "198.51.100.1",
                port: "443",
                transport: "TCP",
                blocked: false
            )
        }
        session.store.send(.received(.init(rows: rows)))
        session.store.send(.located(["192.0.2.1": "US", "198.51.100.1": "GB"]))
        let ids = session.store.activityTree.roots
        let renderer = DefaultRenderer()
        var durations: [Double] = []
        var navigation: [Double] = []
        let clock = ContinuousClock()
        for index in 0 ..< 24 {
            let start = clock.now
            session.store.send(.selectNode(ids[index % ids.count]))
            let selected = start.duration(to: clock.now).components
            navigation.append(Double(selected.seconds) * 1000 + Double(selected.attoseconds) / 1e15)
            let frame = renderer.render(
                MonitorDashboard(session: session)
                    .environment(\.terminalSize, CellSize(width: 140, height: 42))
                    .frame(width: 140, height: 42),
                proposal: .init(width: 140, height: 42)
            )
            let elapsed = start.duration(to: clock.now).components
            if index > 3 {
                durations.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            }
            #expect(frame.diagnostics.runtime.issues.isEmpty)
        }
        durations.sort()
        navigation.sort()
        print("NARK_SELECTION median_ms=\(navigation[navigation.count / 2])")
        print(
            "NARK_NAVIGATION frames=\(durations.count) median_ms=\(durations[durations.count / 2]) p95_ms=\(durations[durations.count - 2])"
        )
    }
}
