import Geography
import SwiftTUI
import Vocabulary

extension UI {

    public struct WorldMap<Concept: L & I_nark_ui_component_map>: View {

        @Environment(\.terminalAppearance) private var appearance

        public struct Destination: Equatable, Sendable {

            public let code: String
            public let highlighted: Bool
            public let blocked: Bool
            public let mixed: Bool
            public init(
                code: String,
                highlighted: Bool,
                blocked: Bool = false,
                mixed: Bool = false
            ) {
                self.code = code
                self.highlighted = highlighted
                self.blocked = blocked
                self.mixed = mixed
            }
        }

        public let concept: Concept
        private let destinations: [Destination]
        private let showsDestinations: Bool
        public init(_ concept: Concept, countries: Set<String>) {
            self.concept = concept
            destinations = countries.sorted().map { Destination(code: $0, highlighted: true) }
            showsDestinations = false
        }

        public init(_ concept: Concept, destinations: [Destination]) {
            self.concept = concept
            self.destinations = destinations
            showsDestinations = true
        }

        public var body: some View {
            Canvas(CountryDrawing(
                destinations: destinations.map { .init(
                    code: $0.code,
                    highlighted: $0.highlighted,
                    blocked: $0.blocked,
                    mixed: $0.mixed
                ) },
                showsDestinations: showsDestinations,
                theme: appearance.synthesizedTheme()
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(
                "Offline peer countries; selected countries and destination markers"
            )
        }
    }
}

private struct CountryDrawing: CanvasDrawing {

    struct Destination: Equatable, Sendable {

        let code: String
        let highlighted: Bool
        let blocked: Bool
        let mixed: Bool
        func color(in theme: Theme) -> Color {
            if !highlighted {
                return theme.separator
            }
            return mixed ? theme.warning : blocked ? theme.danger : theme.success
        }
    }

    let destinations: [Destination]
    let showsDestinations: Bool
    let theme: Theme
    func draw(into context: inout CanvasContext) {
        let width = Double(context.size.width)
        let height = Double(context.size.height)
        let availableHeight = max(0, height - (showsDestinations ? 3 : 0))
        // Equirectangular projection; terminal cells are about twice as tall as wide.
        let mapWidth = min(width, availableHeight * 4.9655)
        let mapHeight = mapWidth / 4.9655
        guard mapWidth > 0, mapHeight > 0 else {
            return
        }
        let left = (width - mapWidth) / 2
        let top = (availableHeight - mapHeight) / 2
        let byCountry = Dictionary(
            destinations.map { ($0.code, $0) },
            uniquingKeysWith: { _, last in last }
        )
        let land = theme.background.mixed(with: theme.muted, amount: 0.4)
        for y in 0 ..< Int(mapHeight * 4) {
            for x in 0 ..< Int(mapWidth * 2) {
                guard let code = World.bundled.country(
                    x: min(World.width - 1, Int(Double(x) / (mapWidth * 2) * Double(World.width))),
                    y: min(
                        World.height - 1,
                        Int(Double(y) / (mapHeight * 4) * Double(World.height))
                    )
                ) else {
                    continue
                }
                let color = byCountry[code].map { $0.highlighted
                    ? (showsDestinations ? $0.color(in: theme) : theme.tint)
                    : theme.muted
                } ?? land
                context.setPixel(
                    at: .init(x: left + Double(x) / 2, y: top + Double(y) / 4),
                    foreground: color
                )
            }
        }
        guard showsDestinations else {
            return
        }
        let local = Point(x: min(5, width / 4), y: height - 1)
        let unknown = Point(x: max(width - 7, width * 3 / 4), y: height - 1)
        func endpoint(_ code: String) -> Point {
            if code == "LOCAL" {
                return local
            }
            guard
                let point = World.countryPoints[code],
                (-60 ... 85).contains(point.latitude)
            else {
                return unknown
            }
            return Point(
                x: left + (point.longitude + 180) / 360 * mapWidth,
                y: top + (85 - point.latitude) / 145 * mapHeight
            )
        }
        // Canvas paints Braille pixels over direct cells regardless of write order.
        // Clear the underlying samples before placing labels and endpoint markers.
        func cell(_ character: Character, x: Int, y: Int, color: Color) {
            for sy in 0 ..< 4 {
                for sx in 0 ..< 2 {
                    context.clearPixel(at: .init(
                        x: Double(x) + Double(sx) / 2,
                        y: Double(y) + Double(sy) / 4
                    ))
                }
            }
            context.setCell(at: .init(x: x, y: y), character: character, foreground: color)
        }
        for destination in destinations.sorted(by: { !$0.highlighted && $1.highlighted }) {
            let end = endpoint(destination.code)
            cell(
                destination.highlighted ? "●" : "·",
                x: Int(end.x),
                y: Int(end.y),
                color: destination.color(in: theme)
            )
        }
        func label(_ text: String, x: Int, color: Color) {
            for (offset, character) in text.enumerated() {
                cell(character, x: x + offset, y: Int(height) - 1, color: color)
            }
        }
        if destinations.contains(where: { $0.code == "LOCAL" }) {
            label(
                "● Local",
                x: 0,
                color: destinations.first { $0.code == "LOCAL" }!.color(in: theme)
            )
        }
        if
            destinations
                .contains(where: { $0.code == "ZZ" || World.countryPoints[$0.code] == nil })
        {
            label(
                "● Unknown",
                x: max(0, Int(width) - 9),
                color: theme.muted
            )
        }
    }
}
