import Geography
import SwiftTUI
import Vocabulary

extension UI {

    public struct WorldMap<Concept: L & I_nark_ui_component_map>: View, Equatable {

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
        private let size: CellSize?

        public init(_ concept: Concept, countries: Set<String>) {
            self.concept = concept
            destinations = countries.sorted().map { Destination(code: $0, highlighted: true) }
            showsDestinations = false
            size = nil
        }

        public init(_ concept: Concept, destinations: [Destination], size: CellSize? = nil) {
            self.concept = concept
            self.destinations = destinations
            showsDestinations = true
            self.size = size
        }

        nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.concept == rhs.concept && lhs.destinations == rhs.destinations
                && lhs.showsDestinations == rhs.showsDestinations && lhs.size == rhs.size
        }

        public var body: some View {
            let theme = appearance.synthesizedTheme()
            let drawing = CountryDrawing(
                countries: showsDestinations ? [] : Set(destinations.filter(\.highlighted).map(\.code)),
                reservesLegend: showsDestinations,
                theme: theme
            )
            Group {
                if showsDestinations {
                    if let size {
                        map(size: size, theme: theme)
                    } else {
                        GeometryReader { geometry in
                            map(size: geometry.size, theme: theme)
                        }
                    }
                } else {
                    Canvas(drawing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Offline peer countries; selected destination markers")
        }

        private func map(size: CellSize, theme: Theme) -> some View {
            ZStack(alignment: .topLeading) {
                CountryBase(size: size, theme: theme)
                DestinationMarkers(destinations: destinations, size: size, theme: theme)
            }
        }

    }
}

/// Reuse the sampled geographic asset; Canvas receives only its occupied cells.
private struct CountryBase: View, Equatable {

    let size: CellSize
    let theme: Theme

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.size == rhs.size && lhs.theme == rhs.theme
    }

    var body: some View {
        let mask = CountryMasks.mask(size: size)
        return Canvas(GeographicDrawing(mask: mask, color: theme.background.mixed(with: theme.muted, amount: 0.4)))
            .frame(width: mask.size.width, height: mask.size.height)
            .offset(x: mask.origin.x, y: mask.origin.y)
            .accessibilityHidden(true)
    }
}

private struct GeographicDrawing: CanvasDrawing {

    let mask: CountryMask
    let color: Color

    func draw(into context: inout CanvasContext) {
        for cell in mask.cells {
            context.setCell(at: cell.point, character: cell.glyph, foreground: color)
        }
    }
}

private final class CountryMask: Equatable, Sendable {

    struct Cell: Equatable, Sendable {
        let point: CellPoint
        let glyph: Character
    }

    let viewport: CellSize
    let origin: CellPoint
    let size: CellSize
    let cells: [Cell]

    init(viewport: CellSize) {
        self.viewport = viewport
        let projection = CountryProjection(size: viewport, reservesLegend: true)
        let origin = CellPoint(x: Int(projection.left), y: Int(projection.top))
        self.origin = origin
        let size = CellSize(
            width: max(0, Int((projection.width + projection.left - Double(origin.x)).rounded(.up))),
            height: max(0, Int((projection.height + projection.top - Double(origin.y)).rounded(.up)))
        )
        self.size = size
        var canvas = BrailleCanvas(width: size.width, height: size.height)
        projection.forEachLandSample { x, y, _ in
            canvas.setPixel(x: x - origin.x * 2, y: y - origin.y * 4)
        }
        cells = canvas.cells.enumerated().flatMap { y, row in
            row.enumerated().compactMap { x, cell in
                cell.mask == 0 ? nil : Cell(point: .init(x: x, y: y), glyph: cell.glyph)
            }
        }
    }

    static func == (lhs: CountryMask, rhs: CountryMask) -> Bool {
        lhs === rhs || (
            lhs.viewport == rhs.viewport && lhs.origin == rhs.origin && lhs.size == rhs.size && lhs.cells == rhs.cells
        )
    }
}

/// One sampled asset bounds memory across terminal resizes; palette changes reuse it.
@MainActor private enum CountryMasks {

    private static var cached: CountryMask?

    static func mask(size: CellSize) -> CountryMask {
        if let cached, cached.viewport == size {
            return cached
        }
        let mask = CountryMask(viewport: size)
        cached = mask
        return mask
    }
}

/// The outline stays unchanged as focus moves. Live markers have cell-sized bounds.
private struct CountryDrawing: CanvasDrawing {

    let countries: Set<String>
    let reservesLegend: Bool
    let theme: Theme

    func draw(into context: inout CanvasContext) {
        let projection = CountryProjection(size: context.size, reservesLegend: reservesLegend)
        let land = theme.background.mixed(with: theme.muted, amount: 0.4)
        projection.forEachLandSample { x, y, code in
            context.setPixel(
                at: .init(x: Double(x) / 2, y: Double(y) / 4),
                foreground: countries.contains(code) ? theme.tint : land
            )
        }
    }
}

private struct DestinationMarkers<Concept: L & I_nark_ui_component_map>: View {

    private struct Marker {
        let point: CellPoint
        let text: String
        let color: Color
        let label: String
    }

    let destinations: [UI.WorldMap<Concept>.Destination]
    let size: CellSize
    let theme: Theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(markers, id: \.point) { marker in
                Text(marker.text, semanticMetadata: .init(accessibilityLabel: marker.label))
                    .foregroundStyle(marker.color)
                    .cellBackground(theme.background)
                    .offset(x: marker.point.x, y: marker.point.y)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Focus changes marker paint, never child order. Merge overlapping country
    /// centres so a focused peer remains visible without reordering the map.
    private var markers: [Marker] {
        let projection = CountryProjection(size: size, reservesLegend: true)
        return Dictionary(grouping: destinations, by: { projection.endpoint($0.code) })
            .map { point, destinations in
                let focused = destinations.filter(\.highlighted)
                let blocked = focused.filter(\.blocked).count
                let mixed = focused.contains(where: \.mixed) || (blocked > 0 && blocked < focused.count)
                let color: Color
                if focused.isEmpty {
                    color = theme.separator
                } else if mixed {
                    color = theme.warning
                } else if blocked == focused.count {
                    color = theme.danger
                } else {
                    color = theme.success
                }
                let text: String
                if destinations.contains(where: { $0.code == "LOCAL" }) {
                    text = "● Local"
                } else if point == projection.endpoint("ZZ") {
                    text = "● Unknown"
                } else {
                    text = focused.isEmpty ? "·" : "●"
                }
                return Marker(
                    point: point,
                    text: text,
                    color: color,
                    label: destinations.map(\.code).sorted().joined(separator: ", ")
                        + (focused.isEmpty ? "" : ", selected")
                )
            }
            .sorted {
                $0.point.y == $1.point.y ? $0.point.x < $1.point.x : $0.point.y < $1.point.y
            }
    }
}

/// Shared geometry for the raster and markers. Terminal cells are about twice as tall as wide.
private struct CountryProjection {

    let size: CellSize
    let width: Double
    let height: Double
    let left: Double
    let top: Double

    init(size: CellSize, reservesLegend: Bool) {
        self.size = size
        let availableHeight = max(0, Double(size.height) - (reservesLegend ? 3 : 0))
        width = min(Double(size.width), availableHeight * 4.9655)
        height = width / 4.9655
        left = (Double(size.width) - width) / 2
        top = (availableHeight - height) / 2
    }

    func forEachLandSample(_ draw: (Int, Int, String) -> Void) {
        guard width > 0, height > 0 else {
            return
        }
        let originX = Int(left * 2)
        let originY = Int(top * 4)
        for y in 0 ..< Int(height * 4) {
            for x in 0 ..< Int(width * 2) {
                guard let code = World.bundled.country(
                    x: min(World.width - 1, Int(Double(x) / (width * 2) * Double(World.width))),
                    y: min(World.height - 1, Int(Double(y) / (height * 4) * Double(World.height)))
                ) else {
                    continue
                }
                draw(originX + x, originY + y, code)
            }
        }
    }

    func endpoint(_ code: String) -> CellPoint {
        if code == "LOCAL" {
            return .init(x: 0, y: max(0, size.height - 1))
        }
        guard let coordinate = World.countryPoints[code], (-60 ... 85).contains(coordinate.latitude) else {
            return .init(x: max(0, size.width - 9), y: max(0, size.height - 1))
        }
        return .init(
            x: Int(left + (coordinate.longitude + 180) / 360 * width),
            y: Int(top + (85 - coordinate.latitude) / 145 * height)
        )
    }
}
