@testable import NarkUI
import SwiftTUI
import Testing
import Vocabulary

@Suite @MainActor struct WorldMapTests {

    @Test func changing_focus_preserves_geography_and_marker_coordinates() {
        let renderer = DefaultRenderer()
        let first = renderer.render(map(selected: "US"), proposal: .init(width: 100, height: 32))
        let second = renderer.render(map(selected: "GB"), proposal: .init(width: 100, height: 32))
        func markers(_ cells: [[RasterCell]]) -> Set<CellPoint> {
            Set(cells.enumerated().flatMap { y, row in
                row.enumerated().compactMap { x, cell in
                    cell.character == "●" || cell.character == "·" ? CellPoint(x: x, y: y) : nil
                }
            })
        }
        let positions = markers(first.rasterSurface.cells)
        #expect(positions.count == 2)
        #expect(markers(second.rasterSurface.cells) == positions)
        let changed = zip(first.rasterSurface.cells, second.rasterSurface.cells).flatMap { old, new in
            zip(old, new).filter { $0 != $1 }
        }
        #expect(changed.count == 2)
        #expect(first.diagnostics.runtime.issues.isEmpty)
        #expect(second.diagnostics.runtime.issues.isEmpty)
    }

    private func map(selected: String) -> some View {
        UI.WorldMap(
            nark.ux.monitor.map,
            destinations: [
                .init(code: "US", highlighted: selected == "US"),
                .init(code: "GB", highlighted: selected == "GB")
            ],
            size: .init(width: 100, height: 32)
        )
        .frame(width: 100, height: 32)
        .background(.theme.background)
    }
}
