import Control
import Firewall
import Monitor
@testable import NarkApplication
import NarkUI
import SwiftTUI
import SwiftTUIRuntime
import Testing
import Vocabulary

@Suite @MainActor struct ThemeTests {

    private func appearance(_ theme: Theme) -> TerminalAppearance {
        .init(
            foregroundColor: theme.foreground,
            backgroundColor: theme.background,
            tintColor: theme.tint,
            palette: .init(indexedColors: [
                1: theme.danger, 2: theme.success, 3: theme.warning,
                4: theme.link, 6: theme.info,
            ]),
            colorSchemeContrast: .standard,
            source: .override
        )
    }

    @Test func semantic_paints_follow_appearance_changes_on_the_same_renderer() throws {
        let renderer = DefaultRenderer()
        for theme in [Theme.light, .dark, .light] {
            let frame = renderer.render(
                Text("X")
                    .foregroundStyle(.theme.foreground)
                    .background(.theme.background)
                    .environment(\.terminalAppearance, appearance(theme)),
                proposal: .init(width: 1, height: 1)
            )
            let cell = try #require(frame.rasterSurface.cells.first?.first)
            #expect(cell.style?.foregroundColor?.hexString() == theme.foreground.hexString())
            #expect(cell.style?.backgroundColor?.hexString() == theme.background.hexString())
        }
    }

    @Test func explicit_presets_remain_available_as_shape_styles() throws {
        let light = DefaultRenderer().render(
            Text("X").foregroundStyle(.light.foreground).background(.light.background)
        )
        let dark = DefaultRenderer().render(
            Text("X").foregroundStyle(.dark.foreground).background(.dark.background)
        )
        #expect(light.rasterSurface.cells[0][0].style?.foregroundColor?.hexString() ==
            Theme.light.foreground.hexString())
        #expect(dark.rasterSurface.cells[0][0].style?.foregroundColor?.hexString() == Theme.dark.foreground.hexString())
    }

    @Test(arguments: [Theme.light, .dark])
    func monitor_pages_follow_terminal_background_and_preserve_readable_text(theme: Theme) throws {
        let session = MonitorFeature.Session(client: .init { _ in .init() })
        for page in [MonitorFeature.Page.home, .activity, .rules] {
            session.store.send(.show(page))
            let frame = DefaultRenderer().render(
                MonitorDashboard(session: session)
                    .frame(width: 100, height: 32)
                    .environment(\.terminalSize, .init(width: 100, height: 32))
                    .environment(\.terminalAppearance, appearance(theme)),
                proposal: .init(width: 100, height: 32)
            )
            let cell = try #require(frame.rasterSurface.cells.joined().first { $0.character == "N" })
            let ink = try #require(cell.style?.foregroundColor)
            #expect(cell.style?.backgroundColor?.hexString() == theme.background.hexString())
            #expect(ink.contrastRatio(to: theme.background) >= 4.5)
        }
    }

    @Test(arguments: [Theme.light, .dark])
    func chart_and_map_use_the_current_terminal_palette(theme: Theme) throws {
        let appearance = appearance(theme)
        let resolved = appearance.synthesizedTheme()
        let chart = DefaultRenderer().render(
            UI.TrafficChart(nark.ux.monitor.activity, sent: [100], received: [50])
                .frame(width: 40, height: 8)
                .background(.theme.background)
                .environment(\.terminalAppearance, appearance),
            proposal: .init(width: 40, height: 8)
        )
        let chartColors = chart.rasterSurface.cells.joined().compactMap { $0.style?.foregroundColor?.hexString() }
        #expect(chartColors.contains(resolved.info.hexString()))
        #expect(chartColors.contains(resolved.link.hexString()))

        let map = DefaultRenderer().render(
            UI.WorldMap(nark.ux.monitor.map, destinations: [.init(code: "US", highlighted: true, blocked: true)])
                .frame(width: 60, height: 20)
                .background(.theme.background)
                .environment(\.terminalAppearance, appearance),
            proposal: .init(width: 60, height: 20)
        )
        let marker = try #require(map.rasterSurface.cells.joined().first { $0.character == "●" })
        #expect(marker.style?.foregroundColor?.hexString() == resolved.danger.hexString())
    }
}
